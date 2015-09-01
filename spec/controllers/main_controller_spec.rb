require 'spec_helper'
require 'rails_helper'

describe MainController do

  describe "Create a new message" do

    it "should throw a 400 when no arguments are passed" do
      response = post :create_new_message
      response.status.should eq 400
    end

    it "should throw a 400 when only one argument is passed" do
      response = post :create_new_message, :username => "test"
      response.status.should eq 400
      response = post :create_new_message, :text => "this is text"
      response.status.should eq 400
    end

    it "should create a new chat message, and return 201" do
      response = post :create_new_message, :username => "test", :text => "this is text"
      response.status.should eq 201
      unexpired_chats = subject.get_unexpired_chats
      unexpired_chats.length.should eq 1
      unexpired_chats[0][:id].should eq "1"
    end

    it "should create a new chat message with custom timeout" do
      response = post :create_new_message, :username => "another_test", :text => "more text", :timeout => 0
      response.status.should eq 201
      unexpired_chats = subject.get_unexpired_chats
      unexpired_chats.length.should eq 2
      expired_chats = subject.get_expired_chats
      # Should not be expired until /chats/:username is called which forces all unexpired chats to expire
      expired_chats.length.should eq 0
    end
  end

  describe "Get a chat id" do

    it "should throw a 404 when id is nonexistent" do
      response = get :get_chat_by_id, :id => "3"
      response.status.should eq 404
    end

    it "should not throw a 404 when that id now exists" do
      post :create_new_message, :username => "test", :text => "test"
      response = get :get_chat_by_id, :id => "3"
      response.status.should eq 200
      unexpired_chats = subject.get_unexpired_chats
      unexpired_chats.length.should eq 3
    end

    it "should return 200 when an already existing id is queried" do
      response = get :get_chat_by_id, :id => "1"
      response.status.should eq 200
    end
  end

  describe "Get chats for username" do

    # This is because chat ids must be generated on creation, but chat usernames may be wiped when expired
    it "should throw a 200 when username is nonexistent" do
      response = get :get_chats_by_username, :username => "gobbledegook"
      response.status.should eq 200
    end

    it "should return all chats for username test and expire those chats immediately" do
      response = get :get_chats_by_username, :username => "test"
      response.status.should eq 200
      expired_chats = subject.get_expired_chats
      expired_chats.length.should eq 3
    end
  end
end
