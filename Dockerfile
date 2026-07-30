FROM ruby:3.4-slim AS builder

# puma and nio4r ship native extensions, so the build stage needs a compiler.
# It is thrown away -- only the resolved bundle is copied into the runtime stage.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# throw errors if Gemfile has been modified since Gemfile.lock
ENV BUNDLE_FROZEN=true

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /usr/local/bundle/cache


FROM ruby:3.4-slim AS runtime

ENV BUNDLE_FROZEN=true

WORKDIR /usr/src/app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock github_webhooks.rb ./
COPY config ./config

EXPOSE 4567

CMD ["/usr/local/bin/ruby", "./github_webhooks.rb", "-o", "0.0.0.0"]
