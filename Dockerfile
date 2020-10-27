FROM hexpm/elixir:1.10.3-erlang-23.0.1-alpine-3.11.6 AS builder

WORKDIR /root

# Install Hex+Rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# Install git
RUN apk --update add git make

ENV MIX_ENV=prod

WORKDIR /root

ADD mix.exs mix.exs
ADD mix.lock mix.lock
ADD config/config.exs config/prod.exs config/prod*.exs config/

RUN mix do deps.get --only prod, deps.compile

ADD . .

RUN mix do compile, release

# Second stage: copies the files from the builder stage
FROM alpine:3.11.6

RUN apk add --update libssl1.1 ncurses-libs bash curl dumb-init \
    && rm -rf /var/cache/apk

# Create non-root user
RUN addgroup -S tablespoon && adduser -S -G tablespoon tablespoon
USER tablespoon
WORKDIR /home/tablespoon

# Set environment
ENV MIX_ENV=prod TERM=xterm LANG=C.UTF-8 REPLACE_OS_VARS=true

COPY --from=builder --chown=tablespoon:tablespoon /root/_build/prod/rel /home/tablespoon/rel

# Ensure SSL support is enabled
RUN /home/tablespoon/rel/tablespoon/bin/tablespoon eval ":crypto.supports()"

 # HTTP
EXPOSE 4000
 # TCP (TransitMaster)
EXPOSE 9006

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

HEALTHCHECK CMD ["/home/tablespoon/rel/tablespoon/bin/tablespoon", "rpc", "1 + 1"]
CMD ["/home/tablespoon/rel/tablespoon/bin/tablespoon", "start"]
