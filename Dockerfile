FROM elixir:1.13.4-slim AS builderish

WORKDIR /app

COPY mix.exs .
COPY mix.lock .
COPY .formatter.exs .

RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get

COPY lib/ ./lib/
COPY config/ ./config/

ENV MIX_ENV=prod
RUN mix release

FROM elixir:1.13.4-slim

RUN apt-get update && apt-get install -y redis-server supervisor adduser sudo

RUN useradd -m rabil && echo "rabil:rabil" | chpasswd && adduser rabil sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /app

COPY --from=builderish /app/_build/prod/rel/prod/ ./_build/prod/rel/prod/

USER rabil

ARG SRH_MODE
ENV SRH_MODE=${SRH_MODE}

ARG SRH_TOKEN
ENV SRH_TOKEN=${SRH_TOKEN}

ARG SRH_CONNECTION_STRING
ENV SRH_CONNECTION_STRING=${SRH_CONNECTION_STRING}

ENV SRH_PORT=7860
EXPOSE 7860

COPY docker/supervisor.conf /etc/supervisor/conf.d/supervisor.conf
COPY docker/redis.conf /etc/redis/redis.conf

RUN sudo chmod -R 777 /etc/redis/

RUN sudo chown -R rabil /app

RUN sudo mkdir -p /etc/lib/redis
RUN sudo chmod -R 777 /etc/lib/redis

ENV MIX_ENV=prod

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisor.conf"]
