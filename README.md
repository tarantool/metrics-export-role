<a href='https://coveralls.io/github/tarantool/metrics-export-role?branch=master'>
<img src='https://coveralls.io/repos/github/tarantool/metrics-export-role/badge.svg?branch=master' alt='Coverage Status' />
</a>

# metrics-export-role

`roles.metrics-export` is a role for Tarantool 3. It allows to export metrics
from Tarantool 3. For now only export via HTTP is supported.

## Usage

1. Add the `metrics-export-role` package to dependencies in the .rockspec file.

```Lua
dependencies = {
    ...
    'metrics-export-role == 0.1.0-1',
    ...
}
```

And re-build an application:

```shell
tt build
```

Be careful, it is better to use a latest release version.

2. Enable and [configure](https://www.tarantool.io/en/doc/latest/concepts/configuration/)
the `roles.metrics-export` role for a Tarantool 3 instance. Use [httpd role](https://github.com/tarantool/http?tab=readme-ov-file#roles)
or `listen` field in to configure server instances. See below to get more detailed information about it.

```yaml
groups:
  group-001:
    replicasets:
      replicaset-001:
        instances:
          master:
            roles: [roles.httpd, roles.metrics-export]
            roles_cfg:
              roles.httpd:
                default:
                - listen: '127.0.0.1:8083'
                additional:
                - listen: 8084
              roles.metrics-export:
                http:
                - endpoints:
                  - path: /metrics/json
                    format: json
                - server: 'additional'
                  endpoints:
                  - path: /metrics/prometheus
                    format: prometheus
                - listen: 8081
                  endpoints:
                  - path: /metrics/json
                    format: json
                  - path: /metrics/prometheus/
                    format: prometheus
                - listen: 'my_host:8082'
                  endpoints:
                  - path: /metrics/prometheus
                    format: prometheus
                  - path: /metrics/json/
                    format: json
```

In the example above, we configure four HTTP servers. There are serveral server fields:

* first with `server` field which refers to an `additional` server in the `httpd` role;
* the next one, with no info about server, is configured with `default` name in `httpd` config;
* and the last two `listen` fields (`0.0.0.0:8081` and `my_host:8082`) that are listed directly.

The servers will be running on the `master` Tarantool instance.

Each server has two endpoints:

* `/metrics/json` exports metrics with JSON format.
* `/metrics/prometheus` exports metrics with Prometheus-compatible format.

## Configuration

The role configuration at the top level could be described as:

```yaml
export_target: opts
```

### http target

For now only `http` target is supported. The target allows to export metrics via
HTTP-servers. The target could be configured as an array of servers.

Each server must have `listen` param that could be a port (number) or a string
in the format `host:port`. The address will be used by HTTP server to listen
requests.

Each server could have `endpoints` param as an array of endpoints to process
incoming requests. An individual endpoint can be described as:

```yaml
- path: /path/to/export/on/the/server
  format: format_to_export
```

Optionally, you can enable
[http metrics](https://www.tarantool.io/en/doc/latest/reference/reference_lua/metrics/#collecting-http-metrics)
for each endpoint. For this you should
set `metrics.enabled` to `true`:

```yaml
- path: /path/to/export/on/the/server
  format: format_to_export
  metrics:
    enabled: true
```

For now only `json` and `prometheus` formats are supported.

### Integration with httpd role

Use [httpd role](https://github.com/tarantool/http?tab=readme-ov-file#roles) as well.
To enable it, you need to fill `server` field with name that was configured in `roles.httpd` block
instead of `listen` like it was earlier. To configure `httpd` role you need to write block in roles_cfg
section:

```yaml
roles_cfg:
  roles.httpd:
    default:
    - listen: 8081
    additional:
    - listen: '127.0.0.1:8082'
```

After it you can use `server` name in `roles.metrics-export` block. If `server` and `listen` names
wasn't provided, the `default` server from `httpd` role configuration will be used:

```yaml
roles.metrics-export:
  http:
  - server: 'additional'
    endpoints:
    ...
  - endpoints:
    ...
```

So now it is possible to mix `server` and `listen` parameteres.

Let's put it all together now:

```yaml
roles_cfg:
  roles.httpd:
    default:
    - listen: 8081
    additional:
    - listen: '127.0.0.1:8082'
  roles.metrics-export:
    http:
    - listen: 8081
      endpoints:
      - path: /metrics
        format: json
      - path: /metrics/prometheus/
        format: prometheus
    - listen: '127.0.0.1:8082'
      endpoints:
      - path: /metrics/
        format: json
        metrics:
          enabled: true
    - server: 'additional'
      endpoints:
      - path: /metrics
        format: json
    - endpoints:
      - path: /metrics
        format: prometheus
        metrics:
          enabled: true
```

With this configuration, metrics can be obtained on this machine with the
Tarantool instance as follows:

```shell
curl -XGET 127.0.0.1:8081/metrics
# Metrics will be returned in JSON format.
curl -XGET 127.0.0.1:8081/metrics/prometheus
# Metrics will be returned in Prometheus-compatible format.
curl -XGET 127.0.0.1:8082/metrics
# Metrics will be returned in JSON format.
```

## Development

First you need to clone the repository:

```shell
git clone https://github.com/tarantool/metrics-export-role
cd metrics-export-role
```

After that you need to install dependencies (`tt` is required):

```shell
make deps
```

At this point you could run tests (`tarantool` 3 is required):

```shell
make test
```

And a linter:

```shell
make luacheck
```
