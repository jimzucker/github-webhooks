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

def read_properties()
  if(File.exist?('.webhook_properties'))
    return JavaProperties.load('.webhook_properties')
  else
    puts '[ERROR] You must have a java style properties file .webhook_properties with githubToken=xx defined'
    exit(1)
  end
end

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

def exec_request(method, success_code, url, request_body, message, exit_on_error) 
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
  if !response.code.eql?(success_code) && exit_on_error
    puts '[ERROR] Executing http call, result code = ' + response.code + ' url= ' + url
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
def repository_default(webhook_action, webhook_object,webhook_payload)

  #partse params
  repository_full_name = webhook_payload['repository']['full_name']
  sender_login = webhook_payload['sender']['login']
  puts "[INFO] Processing object= #{webhook_object}, action= #{webhook_action} on repo= #{repository_full_name} by #{sender_login}"


  #get authorized user info
  response = exec_request('Get','200','user', '','Getting Authorized User', true)
  authorized_user_json = JSON.parse(response.read_body)
  authorized_user_login = authorized_user_json['login']
  authorized_user_name = authorized_user_json['name']
  authorized_user_email = authorized_user_json['email']    #returns nil if Primary email is not public
  if ! authorized_user_email
    puts "[ERROR] Primary email address must be public which provides an email entry for /user endpoint for authorized user executing webhook, user_login=#{authorized_user_login}"
    puts authorized_user_response.read_body
    exit(1)
  end

  #check if readme exists, if not create it
  response = exec_request('Get','200',"repos/#{repository_full_name}/contents/README.md", '', 'Checking existance of README.md', false)
  if !response.code.eql?('200')
    #add a README.md if one does not exist, see issue #2 branch protection API cannot work if repo is empty
    readme_content_base64=Base64.strict_encode64("\# #{repository_full_name}")
    readme_config = "{\"message\": \"my commit message\",  \"sender_login\": \{\"name\": \"#{authorized_user_name}\",\"email\": \"#{authorized_user_name}\" \}, \"content\": \"#{readme_content_base64}\"}"
    response = exec_request('Put','201',"repos/#{repository_full_name}/contents/README.md", readme_config, 'Creating README.md(Note:repository must be initialized for branch permissions api to work).', true)
  end

  #set repo defaults (Must due this after creating readme)
  repo_config = read_config_file('new_repo_config.json')
  response = exec_request('Patch','200',"repos/#{repository_full_name}", repo_config, 'Defaulting Repository Settings', true)

  #protect master branch 
  branch_config = read_config_file('new_master_branch_config.json')
  response = exec_request('Put','200',"repos/#{repository_full_name}/branches/master/protection", branch_config, 'Protecting master branch', true)

  #add an issue to document the changes
  request_body = "{\"title\": \"Ran webook to default repository settings & protected master branch\",\"body\" : \" @#{authorized_user_login} set default respository settings and protected the master branch.\"}"
  response = exec_request('Post','201',"repos/#{repository_full_name}/issues", request_body, 'Defaulting Repository Settings', true)

end

def repository_webhook(webhook_action, webhook_object, webhook_payload)
  #validate inputs
  if ! webhook_object.casecmp?('repository') 
    puts "[ERROR] Invalid call to repository_webhook for object = #{webhook_object}"
    exit(1)
  end

  # we want to only take action on the 'created' event on a repository
  # Project created, updated, or deleted
  # Note: When a repository is created we can get many other events depending on how the webhook is configured
  #  so we will ingore them
  case webhook_action.downcase
    when 'created'
      repository_default(webhook_action, webhook_object,webhook_payload)
    else
      puts "[INFO] Ignoring object = #{webhook_object}, action = #{webhook_action}"
  end
end
##################################################################################################

##################################################################################################
# Main hook
#
post '/github_webhook' do
  webhook_payload = JSON.parse(request.body.read)

  #Payloads https://developer.github.com/v3/activity/events/types/
  webhook_action = webhook_payload['action']
  webhook_keys = webhook_payload.keys
  webhook_object = webhook_keys [1]

  #
  #Print the message to the log
  #
  #puts JSON.pretty_generate(webhook_payload)
  #puts '--------------------------------------------------------------'

  case webhook_object.downcase
    when 'repository'
      repository_webhook(webhook_action, webhook_object, webhook_payload)
    else
      puts "[INFO] Ignoring object = #{webhook_object}, action = #{webhook_action}"
  end

end

##################################################################################################
