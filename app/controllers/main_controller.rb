require 'thread'
require 'pry'
require 'firebase'

class MainController < ApplicationController

  @@message_id = 0

  # This lock is provided to make the post operation including the ID threadsafe
  @@lock = Mutex.new

  # This is the root defalt object we use in order to maintain our "table".  Firebase is finicky when it comes
  # to its structure and each "table" must contain at least one element, or else the table itself gets deleted
  # Set the timeout arbitrarily long from now so that it never expires, and remains in this "table"
  DEFAULT_VALUE = { :root => { :id => -1, :timeout => Time.now + 30.years, :text => "", :username => "" }}
  def initialize
    # Firebase client for querying database service
    # Ideally pull the url from a config file
    @client = Firebase::Client.new('https://mfp-chat-dev.firebaseio.com')
  end

  def create_new_message

    # 400 is the appropriate HTTP response if all the necessary params are not provided
    if (params.nil? || params[:username].nil? || params[:text].nil?)
      render :json => { :message => "Bad request: you must provide a username and text for the mesage", :status => 400 }, :status => 400
      return
    end

    # Set the timeout based on whether user has put it in or not in the request
    timeout = (params[:timeout].present?) ? (params[:timeout].to_i).minutes : 60.minutes

    # Setup the chat to add to the list based on params
    input_chat = { :username => params[:username], :text => params[:text], :timeout => Time.now + timeout }
    
    # Using Mutex makes this threadsafe
    @@lock.synchronize do
      @@message_id += 1
    end
    input_chat[:id] = @@message_id.to_s

    # Add to the list of unexpired chats.  This service does not expire chats on its own, but requires
    # a GET request from the client to move the chat to the necessary list
    if post_to_firebase(input_chat) == true
      render :json => { :id => @@message_id }, :status => 201
    end
  end

  def get_chat_by_id

    # 400 is the appropriate HTTP response if an ID is not given
    if (params.nil? || params[:id].nil?)
      render :json => { :message => "Bad request: you must provide an id to query by id", :status => 400 }, :status => 400
      return
    end

    # Build a list of chats (should only be 1, but the spec was odd about this)
    response_list = []

    expired_chats = @client.get("expired-chats/#{params[:id]}")
    unexpired_chats = @client.get ("unexpired-chats/#{params[:id]}")

    if expired_chats.nil? || unexpired_chats.nil?
      render :json => { :message => "Error querying upstream database", :status => 500 }, :status => 500
      return
    end

    # Since we have a successful response, now can get required fields
    # Chat IDs can be unique, so only one possible response
    expired_chats = expired_chats.body
    unexpired_chats = unexpired_chats.body

    if expired_chats.nil? && unexpired_chats.nil?
      render :json => { :message => "Cannot find chat with id: '#{params[:id]}'", :status => 404 }, :status => 404
      return
    else
      render :json => (expired_chats.nil? ? unexpired_chats : expired_chats), :status => 200
      return
    end
  end

  def get_chats_by_username

    # 400 is the appropriate HTTP response if a username is not given
    if (params.nil? || params[:username].nil?)
      render :json => { :message => "Bad request: you must provide a username to query with", :status => 400 }, status => 400
      return
    end

    unexpired_chats = @client.get("unexpired-chats")

    if unexpired_chats.nil?
      render :json => { :message => "Error querying upstream database.", :status => 500 }, :status => 500
      return
    end

    unexpired_chats = unexpired_chats.body.nil? ? [] : unexpired_chats.body

    # One is presented as a response list to user, the other is used to compute deletes from unexpired list
    # Concurrent modification is a nasty little thing
    response_list = []
    deletions = {}

    unexpired_chats.each {
      |key, chat|
      # Again, to symbolize the keys to keep logic consistent
      chat.symbolize_keys! if chat.class == Hash

      # Freezing the time now so that the following two operations depend on the same time
      curr_time = Time.now

      chat_timeout = Time.parse(chat[:timeout])
      response_list << { :id => chat[:id], :text => chat[:text] } if (chat[:username] == params[:username] && chat_timeout >= curr_time)
      deletions[key] = chat if (chat[:username] == params[:username] || chat_timeout < curr_time)
    }

    # Faster performance to render and then perform DB operations
    render :json => response_list


    # Instead of deleting all of the elements from table, set it to default value is easier
    delete_unexpired = @client.set("unexpired-chats", DEFAULT_VALUE)
    if delete_unexpired.nil?
      render :json => { :message => "Error querying upstream database.", :status => 500 }, :status => 500
      return
    end

    # Sets all of the deletions from unexpired list to expired
    deletions.each {
      |key, value|
      push_expire = @client.set("expired-chats/#{key}", value)
      if push_expire.nil?
        render :json => { :message => "Error querying upstream database.", :status => 500 }, :status => 500
        return
      end
    }
  end

  # Private utility methods used above
  private

  def post_to_firebase(input)
    response = @client.set("unexpired-chats/#{input[:id]}", input)
    return response.success?
  end
end
