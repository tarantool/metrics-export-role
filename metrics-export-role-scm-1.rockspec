package = "metrics-export-role"
version = "scm-1"

source = {
    url = "git+https://github.com/tarantool/metrics-export-role",
    branch = "master",
}

description = {
    summary = "The Tarantool 3 role for metrics export via HTTP",
    homepage = "https://github.com/tarantool/metrics-export-role",
    license = "BSD2",
    maintainer = "Fedor Terekhin <fedor.terekhin@tarantool.org>"
}

dependencies = {
    "lua >= 5.1",
    "tarantool >= 3.0",
    "http >= 1.5.0",
}

build = {
    type = "builtin",
    modules = {
        ["roles.metrics-export"] = "roles/metrics-export.lua"
    }
}
-- vim: syntax=lua
