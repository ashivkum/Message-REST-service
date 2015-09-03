require 'thread'

class MainController < ApplicationController

  @@message_id = 0

  # This lock is provided to make the post operation including the ID threadsafe
  @@lock = Mutex.new

  # Implementing hot/cold storage system using 2 different arrays
  # Ideally this should be done with a database, but for simplicity using this
  # So long as the file is not modified upon building, executing, and testing this service, the current setup will work
  @@unexpired_chats = []
  @@expired_chats = []

  def initialize
  end

  def create_new_message

    # 400 is the appropriate HTTP response if all the necessary params are not provided
    if (params.nil? || params[:username].nil? || params[:text].nil?)
      render :json => { :message => "Bad request: you must provide a username and text for the mesage", :status => 400 }, :status => 400
      return
    end

    # Set the timeout based on whether user has put it in or not in the request
    timeout = (params[:timeout].present?) ? to_minutes(params[:timeout].to_i) : to_minutes(60)

    # Setup the chat to add to the list based on params
    input_chat = { :username => params[:username], :text => params[:text], :timeout => Time.now + timeout }
    
    # Using Mutex makes this threadsafe
    @@lock.synchronize do
      @@message_id += 1
    end
    input_chat[:id] = @@message_id.to_s

    # Add to the list of unexpired chats.  This service does not expire chats on its own, but requires
    # a GET request from the client to move the chat to the necessary list
    @@unexpired_chats << input_chat
    render :json => { :id => @@message_id }, :status => 201

  end

  def get_chat_by_id

    # 400 is the appropriate HTTP response if an ID is not given
    if (params.nil? || params[:id].nil?)
      render :json => { :message => "Bad request: you must provide an id to query by id", :status => 400 }, :status => 400
      return
    end

    # Build a list of chats (should only be 1, but the spec was odd about this)
    response_list = []

    # This can enumarate through both expired and unexpired chats
    all_chats = @@unexpired_chats | @@expired_chats
    all_chats.each {
      |chat|
      response_list << chat if chat[:id] == params[:id]
    }
    if response_list.empty?
      render :json => { :message => "Cannot find chat with id: '#{params[:id]}'", :status => 404 }, :status => 404
      return
    else
      render :json => response_list, :status => 200
      return
    end
  end

  def get_chats_by_username

    # 400 is the appropriate HTTP response if a username is not given
    if (params.nil? || params[:username].nil?)
      render :json => { :message => "Bad request: you must provide a username to query with", :status => 400 }, status => 400
      return
    end

    # One is presented as a response list to user, the other is used to compute deletes from unexpired list
    # Concurrent modification is a nasty little thing
    response_list = []
    to_delete = []
    @@unexpired_chats.each {
      |chat|
      # Freezing the time now so that the following two operations depend on the same time
      curr_time = Time.now
      response_list << { :id => chat[:id], :text => chat[:text] } if (chat[:username] == params[:username] && chat[:timeout] >= curr_time)
      to_delete << chat if (chat[:username] == params[:username] || chat[:timeout] < curr_time)
    }

    # This loop is done again because concurrently deleting from unexpired chats in the previous loop results in unpredictable behaviour
    to_delete.each {
      |chat|
      @@unexpired_chats.delete(chat)
      @@expired_chats << chat
    }
    render :json => response_list, :status => 200
  end

  # The following public methods are for testing
  def get_expired_chats
    return @@expired_chats
  end

  def get_unexpired_chats
    return @@unexpired_chats
  end

  # Private utility method used above
  private
  def to_minutes(input)
    return input * 60
  end
end
