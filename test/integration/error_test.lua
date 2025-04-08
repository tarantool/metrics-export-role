local fio = require('fio')
local helpers = require('test.helpers')
local server = require('test.helpers.server')

local t = require('luatest')
local g = t.group()

g.before_all(function()
    helpers.skip_if_unsupported()
end)

g.before_each(function(cg)
    cg.workdir = fio.tempdir()
    fio.mktree(cg.workdir)

    fio.copytree(".rocks", fio.pathjoin(cg.workdir, ".rocks"))
    fio.copytree("roles", fio.pathjoin(cg.workdir, "roles"))
end)

g.after_each(function(cg)
    fio.rmtree(cg.workdir)
end)

g.test_incorrect_httpd_sequense = function(cg)
    cg.server = server:new({
            config_file = fio.abspath(fio.pathjoin('test', 'entrypoint', 'incorrect_roles_sequence.yaml')),
            chdir = cg.workdir,
            alias = 'master',
            workdir = cg.workdir,
    })

    t.assert_error(function()
        cg.server:start({wait_until_ready = true})
    end)

    t.assert_str_contains(
        cg.server.process.output_beautifier.stderr,
        'failed to get server by name "default", check that roles.httpd was already applied'
    )
end
