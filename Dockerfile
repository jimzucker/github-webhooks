FROM ruby:2.6.5

RUN gem install bundler:2.1.4

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock github_webhooks.rb ./
RUN bundle install

COPY config ./config

CMD ["/usr/local/bin/ruby", "./github_webhooks.rb", "-o", "0.0.0.0"]

