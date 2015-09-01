Rails.application.routes.draw do
  post '/chat', to: 'main#create_new_message'
  get '/chat/:id', to: 'main#get_chat_by_id'
  get '/chats/:username', to: 'main#get_chats_by_username'
end
