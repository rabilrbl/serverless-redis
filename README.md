---
title: pkv
emoji: 📈
colorFrom: red
colorTo: pink
sdk: docker
pinned: true
license: mit
---

This is a forked version of [hiett/serverless-redis-http](https://github.com/hiett/serverless-redis-http). We have modified the dockerfile to include redis-server.

# Serverless Redis HTTP (SRH)

A Redis proxy and connection pooler that uses HTTP rather than the Redis binary protocol.\
The aim of this project is to be entirely compatible with Upstash, and work with any Upstash supported Redis version.

Use cases for SRH:
- For usage in your CI pipelines, creating Upstash databases is tedious, or you have lots of parallel runs.
    - See [Using in GitHub Actions](#in-github-actions) on how to quickly get SRH setup for this context.
- For usage inside of Kubernetes, or any network whereby the Redis server is not exposed to the internet.
    - See [Using in Docker Compose](#via-docker-compose) for the various setup options directly using the Docker Container.
- For local development environments, where you have a local Redis server running, or require offline access.
    - See [Using the Docker Command](#via-docker-command), or [Using Docker Compose](#via-docker-compose).

## Differences between Upstash and Redis to note
SRH tests are ran nightly against the `@upstash/redis` JavaScript package. However, there are some minor differences between Upstash's implementation of Redis and the official Redis code.

- The `UNLINK` command will not throw an error when 0 keys are given to it. In Redis, and as such SRH, an error will be thrown.
- In the `ZRANGE` command, in Upstash you are not required to provide `BYSCORE` or `BYLEX` in order to use the `LIMIT` argument. With Redis/SRH, this will throw an error if not provided.
- The Upstash implementation of `RedisJSON` contains a number of subtle differences in what is returned in responses. For this reason, **it is not advisable to use SRH with Redis Stack if you are testing your Upstash implementation that uses JSON commands**. If you don't use any JSON commands, then all is good :)
- **SRH does not implement commands via paths, or accepting the token via a query param**. Only the body method is implemented, which the `@upstash/redis` SDK uses.

### Similarities to note:

Pipelines and Transaction endpoints are also implemented, also using the body data only. You can read more about the RestAPI here: [Upstash Docs on the Rest API](https://docs.upstash.com/redis/features/restapi)

Response encoding is also fully implemented. This is enabled by default by the `@upstash/redis` SDK. You can read more about that here: [Upstash Docs on Hashed Responses](https://docs.upstash.com/redis/sdks/javascriptsdk/troubleshooting#hashed-response)

## How to use with the `@upstash/redis` SDK
Simply set the REST URL and token to where the SRH instance is running. For example:
```ts
import {Redis} from '@upstash/redis';

export const redis = new Redis({
    url: "http://localhost:7860",
    token: "example_token",
});
```

# Setting up SRH
## Via Docker command

#### Running the Docker Container

Once the image is built, you can run the Docker container. The application requires several environment variables to be set, which you can pass during the `docker run` command.

```sh
docker run -d \
  -e SRH_MODE=env \
  -e SRH_TOKEN=<your_token> \
  -e SRH_CONNECTION_STRING=redis://127.0.0.1:6379 \
  -p 7860:7860 \
  rabilrbl/serverless-redis:latest
```

Replace `<your_token>` with your actual configuration values. It will be used to authenticate requests to the Redis http server.

#### Explanation of Arguments

- `-d`: Run the container in detached mode.
- `--name my_elixir_app_container`: Assigns a name to the running container.
- `-e SRH_MODE=env`: Sets the `SRH_MODE` environment variable inside the container.
- `-e SRH_TOKEN=<your_token>`: Sets the `SRH_TOKEN` environment variable inside the container.
- `-e SRH_CONNECTION_STRING=redis://127.0.0.1:6379`: Sets the `SRH_CONNECTION_STRING` environment variable inside the container.
- `-p 7860:7860`: Maps port 7860 on the host to port 7860 in the container.
- `rabilrbl/serverless-redis`: The name of the Docker image to run.

### Supervisor Configuration

The application uses Supervisor to manage processes. The Supervisor configuration file is included in the Docker image at `/etc/supervisor/conf.d/supervisor.conf`.

### Redis Configuration

Redis configuration is included in the Docker image at `/etc/redis/redis.conf`.

### Additional Information

The application is built in production mode (`MIX_ENV=prod`) and expects all dependencies and the release to be present in the `_build/prod/rel/prod/` directory.

For any issues or questions, please refer to the project's documentation or raise an issue on the project's repository.

## In GitHub Actions

SRH works nicely in GitHub Actions because you can run it as a container in a job's services. Simply start a Redis server, and then
SRH alongside it. You don't need to worry about a race condition of the Redis instance not being ready, because SRH doesn't create a Redis connection until the first command comes in.

```yml
name: Test @upstash/redis compatability
on:
  push:
  workflow_dispatch:

env:
  SRH_TOKEN: example_token

jobs:
  container-job:
    runs-on: ubuntu-latest
    container: denoland/deno
    services:
      srh:
        image: rabilrbl/serverless-redis:latest
        env:
          SRH_MODE: env # We are using env mode because we are only connecting to one server.
          SRH_TOKEN: ${{ env.SRH_TOKEN }}
          SRH_CONNECTION_STRING: redis://127.0.0.1:6379

    steps:
      # You can place your normal testing steps here. In this example, we are running SRH against the upstash/upstash-redis test suite.
      - name: Checkout code
        uses: actions/checkout@v3
        with:
          repository: upstash/upstash-redis

      - name: Run @upstash/redis Test Suite
        run: deno test -A ./pkg
        env:
          UPSTASH_REDIS_REST_URL: http://srh:80
          UPSTASH_REDIS_REST_TOKEN: ${{ env.SRH_TOKEN }}
```

# Configuration Options

SRH works with multiple Redis servers, and can pool however many connections you wish it to. It will shut down un-used pools after 15 minutes of inactivity. Upon the next command, it will re-build the pool.

## Connecting to multiple Redis servers at the same time

The examples above use environment variables in order to tell SRH which Redis server to connect to. However, you can also use a configuration JSON file, which lets you create as many connections as you wish. The token provided in each request will decide which pool is used.

Create a JSON file, in this example called `tokens.json`:
```json
{
    "example_token": {
        "srh_id": "some_unique_identifier",
        "connection_string": "redis://localhost:6379",
        "max_connections": 3
    }
}
```
You can provide as many entries to the base object as you wish, and configure the number of max connections per pool. The `srh_id` is used internally to keep track of instances. It can be anything you want.

Once you have created this, mount it to the docker container to the `/app/srh-config/tokens.json` file. Here is an example docker command:

`docker run -it -d -p 8079:80 --name srh --mount type=bind,source=$(pwd)/tokens.json,target=/app/srh-config/tokens.json hiett/serverless-redis-http:latest`

## Environment Variables

| Name | Default Value | Notes |
| ---- | ------------- | ----- |
| SRH_MODE | `file` | Can be `env` or `file`. If `file`, see [Connecting to multiple Redis servers](#connecting-to-multiple-redis-servers-at-the-same-time). If set to `env`, you are required to provide the following environment variables: |
| SRH_TOKEN | `<required if SRH_MODE = env>` | Set the token that the Rest API will require |
| SRH_CONNECTION_STRING | `<required if SRH_MODE = env>` | Sets the connection string to the Redis server. |
| SRH_MAX_CONNECTIONS | `3` | Only used if `SRH_MODE=env`. |
| SRH_PORT | `80` | Configure the port SRH runs on. |
| SRH_IPV6 | `false` | Set to `true` to enabled IPv6 support. |