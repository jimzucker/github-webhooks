#!/usr/local/bin/ruby
# simple webhook demo, see https://developer.github.com/webhooks/configuring/
#
# Pre Requisites
# --------------
# install ngrok see: https://ngrok.com
# install ruby on my mac correctly:https://stackify.com/install-ruby-on-your-mac-everything-you-need-to-get-going/
#   /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
#  Step 1: brew install ruby
#  #update your profile per the output of the brew install
#    #If you need to have ruby first in your PATH run:
#      echo 'export PATH="/usr/local/opt/ruby/bin:$PATH"' >> ~/.zshrc
#    
#     #For compilers to find ruby you may need to set:
#      export LDFLAGS="-L/usr/local/opt/ruby/lib"
#      export CPPFLAGS="-I/usr/local/opt/ruby/include"
#    #For pkg-config to find ruby you may need to set:
#      export PKG_CONFIG_PATH="/usr/local/opt/ruby/lib/pkgconfig"
#
#  #install sinatra-contrib dependency
#    gem install sinatra-contrib
#
#
# Run
# -----------
# expose port: ./ngrok http 4567
#
# Configure webhook with output from ngrok: 
#  <ngrok url>/payload #set payload type to JSON
#  example: https://78e4671d.ngrok.io/payload
#
# start the server: ruby server.rb
#
#
require 'sinatra'
require 'json'
require 'java-properties'
require 'uri'
require 'net/http'

##################################################################################################
  #
  # utilties
  #
def payload_action(webhook_payload)
  return webhook_payload['action']
end

def read_properties()
  if(File.exist?('.webhook_properties'))
    return JavaProperties.load('.webhook_properties')
  else
    puts '[ERROR] You must have a java style properties file .webhook_properties with githubToken=xx defined'
    exit(1)
  end
end

  #
  # parse payload for object of request 
  # the second key in json is the object the 'action' is on
  #
def payload_ojbect(webhook_payload)
  keys = webhook_payload.keys
  return keys [1]
end

def exec_request(method, sucess_code, url, request_body, message) 
  properties = read_properties()
  url = 'https://api.github.com/' + url
  puts "[INFO] #{message}:  method= #{method}, url= #{url}"

  uri = URI(url)
  case method
    when 'Get'
      request = Net::HTTP::Get.new(uri)
    when 'Patch'
      request = Net::HTTP::Patch.new(uri)
    when 'Post'
      request = Net::HTTP::Post.new(uri)
    when 'Put'
      request = Net::HTTP::Put.new(uri)
    else
      puts "[ERROR] unknow method: #{method}"
      exit(1)
  end

  #build request
  request['Authorization'] = 'token ' + properties[:githubToken]
  request['Content-Type'] = 'application/json'
  request["Accept"] = "application/vnd.github.luke-cage-preview+json"  #required for experimental features
  request.body = request_body

  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  response =  https.request(request)
  if !response.code.eql?(sucess_code) 
    puts '[ERROR] Error executing http call, result code = ' + response.code + ' url= ' + url
    puts response.read_body
    exit(1)
  end
  return response
end
##################################################################################################

##################################################################################################
  #
  # process events for repositories
  #

def read_config_file(config_file) 
  config_file = 'config/' + config_file
  if(File.exist?(config_file)) 
    json_body =  File.read(config_file)
  else 
    puts '[ERROR] ' + config_file + ' file missing'
    exit(1)
  end
  return json_body
end

def repository_default(full_name, sender_login)
  #set repo defaults
  repo_config = read_config_file('new_repo_config.json')
  response = exec_request('Patch','200','repos/' + full_name, repo_config, 'Defaulting Repository Settings')

  #protect master branch 
  branch_config = read_config_file('new_master_branch_config.json')
  response = exec_request('Put','200','repos/' + full_name + '/branches/master/protection', branch_config, 'Protecting master branch')

  #add an inssue to document the changes
  request_body = "{\"title\": \"Ran webook to default repository settings & protected master branch\",\"body\" : \" @" + sender_login + " set default respository settings and protected the master branch.\"}"
  response = exec_request('Post','201','repos/' + full_name + '/issues', request_body, 'Defaulting Repository Settings')

end

def repostory_webhook(action, object, webhook_payload)
  #validate inputs
  if ! object.casecmp?('repository') 
    puts "[ERROR] Invalid call to repostory_webhook for object = #{object}"
    exit(1)
  end

  # we want to only take action on the 'created' event on a repository
  # Project created, updated, or deleted
  # Note: When a repository is created we can get many other events depending on how the webhook is configured
  #  so we will ingore them
  case action.downcase
    when 'created'
      full_name = webhook_payload['repository']['full_name']
      sender_login = webhook_payload['sender']['login']
      puts "[INFO] Processing object= #{object}, action= #{action} on repo= #{full_name} by #{sender_login}"
      repository_default(full_name, sender_login)
    else
      puts "[INFO] Ignoring object = #{object}, action = #{action}"
  end
end
##################################################################################################

##################################################################################################
# Main hook
#
post '/github_webhook' do
  webhook_payload = JSON.parse(request.body.read)

  #Payloads https://developer.github.com/v3/activity/events/types/
  action = payload_action(webhook_payload)

  object = payload_ojbect(webhook_payload)

  #for debugging
  #puts "action = #{action}"
  #puts "object = #{object}"

  #
  #Print the message to the log
  #
  #puts JSON.pretty_generate(webhook_payload)
  #puts '--------------------------------------------------------------'

  case object.downcase
    when 'repository'
      repostory_webhook(action, object, webhook_payload)
    else
      puts "[INFO] Ignoring object = #{object}, action = #{action}"
  end

end

##################################################################################################
