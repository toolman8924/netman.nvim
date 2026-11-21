_G._QUIET = true
vim.g.netman_log_level = 0
local SHELL_CONSTANTS = require("netman.tools.shell").CONSTANTS

local describe = require("busted").describe
local it = require("busted").it
local before_each = require("busted").before_each
local after_each = require("busted").after_each

describe("Netman Container", function()
    describe("#URI", function()
        local cache
        before_each(function()
            cache = require("netman.tools.cache"):new()
        end)
        after_each(function()
            cache:clear()
        end)

        it("should parse a file URI", function()
            local uri = "podman://somecontainer/somepath/somefile.txt"
            local parsed_uri = require("netman.providers.container").URI:new(uri, cache)
            local api = require("netman.tools.options").api
            assert.is_equal("somecontainer", parsed_uri.container)
            assert.is_equal(api.ATTRIBUTES.FILE, parsed_uri.type)
            assert.is_equal(api.READ_TYPE.FILE, parsed_uri.return_type)
            assert.is_equal("/somepath/somefile.txt", parsed_uri:to_string())
            assert.is_not_nil(parsed_uri.unique_name)
        end)

        it("should parse a directory URI", function()
            local uri = "podman://somecontainer/somepath/somechildpath/"
            local parsed_uri = require("netman.providers.container").URI:new(uri, cache)
            local api = require("netman.tools.options").api
            assert.is_equal("somecontainer", parsed_uri.container)
            assert.is_equal(api.ATTRIBUTES.DIRECTORY, parsed_uri.type)
            assert.is_equal(api.READ_TYPE.EXPLORE, parsed_uri.return_type)
            assert.is_equal("/somepath/somechildpath/", parsed_uri:to_string())
            assert.is_nil(parsed_uri.unique_name)
        end)

        it("should reject a URI without a protocol prefix", function()
            assert.has_error(function()
                require("netman.providers.container").URI:new("somecontainer///somepath/somefile.txt", cache)
            end)
        end)
    end)

    describe("#_stat_parse", function()
        local function make_container()
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            return container_mod:new("podman", "somecontainer", cache)
        end

        it("should parse find stat output for a file", function()
            local container = make_container()
            local input = "MODE=81ed,BLOCKS=0,BLKSIZE=512,MTIME_SEC=1662860937,USER=root,GROUP=root,INODE=1092025921,PERMISSIONS=755,SIZE=0,TYPE=regular file,NAME=/somefilename"
            local result = container:_stat_parse({input})
            local stat = result['/somefilename']
            assert.is_equal('DESTINATION', stat.FIELD_TYPE)
            assert.is_equal('somefilename', stat.NAME)
            assert.is_equal('81ed', stat.MODE)
            assert.is_equal('0', stat.BLOCKS)
            assert.is_equal('512', stat.BLKSIZE)
            assert.is_equal('1662860937', stat.MTIME_SEC)
            assert.is_equal('root', stat.USER)
            assert.is_equal('root', stat.GROUP)
            assert.is_equal('1092025921', stat.INODE)
            assert.is_equal('755', stat.PERMISSIONS)
            assert.is_equal('0', stat.SIZE)
            assert.is_equal('podman://somecontainer/somefilename', stat.URI)
        end)

        it("should parse find stat output for an empty file", function()
            local container = make_container()
            local input = "MODE=81ed,BLOCKS=0,BLKSIZE=512,MTIME_SEC=1662860937,USER=root,GROUP=root,INODE=1092025921,PERMISSIONS=755,SIZE=0,TYPE=regular empty file,NAME=/somefilename"
            local result = container:_stat_parse({input})
            local stat = result['/somefilename']
            assert.is_equal('DESTINATION', stat.FIELD_TYPE)
            assert.is_equal('somefilename', stat.NAME)
            assert.is_equal('podman://somecontainer/somefilename', stat.URI)
        end)

        it("should parse find stat output for a directory", function()
            local container = make_container()
            local input = "MODE=41ed,BLOCKS=0,BLKSIZE=512,MTIME_SEC=1662860937,USER=root,GROUP=root,INODE=1092025921,PERMISSIONS=755,SIZE=0,TYPE=directory,NAME=/somefilename"
            local result = container:_stat_parse({input})
            local stat = result['/somefilename']
            assert.is_equal('LINK', stat.FIELD_TYPE)
            assert.is_equal('somefilename', stat.NAME)
            assert.is_equal('podman://somecontainer/somefilename/', stat.URI)
        end)

        it("should parse find stat output with absolute path name", function()
            local container = make_container()
            local input = "MODE=41ed,BLOCKS=0,BLKSIZE=512,MTIME_SEC=1662860937,USER=root,GROUP=root,INODE=1092025921,PERMISSIONS=755,SIZE=0,TYPE=directory,NAME=/somepath/somefilename"
            local result = container:_stat_parse({input})
            local stat = result['/somepath/somefilename']
            assert.is_equal('LINK', stat.FIELD_TYPE)
            assert.is_equal('somefilename', stat.NAME)
            assert.is_equal('podman://somecontainer/somepath/somefilename/', stat.URI)
            assert.is_equal('somefilename', stat.ABSOLUTE_PATH[#stat.ABSOLUTE_PATH].name)
            assert.is_equal('podman://somecontainer/somepath/somefilename/', stat.ABSOLUTE_PATH[#stat.ABSOLUTE_PATH].uri)
        end)
    end)

    describe("#cache", function()
        after_each(function()
            package.loaded['netman.providers.container'] = nil
        end)

        it("should reuse container from provider cache", function()
            local cache = require("netman.tools.cache"):new()
            local container_mod = require("netman.providers.container")
            local first = container_mod:new("podman", "somecontainer", cache)
            local second = container_mod:new("podman", "somecontainer", cache)
            assert.is_equal(first, second)
        end)
    end)

    describe("#current_status", function()
        before_each(function()
            package.loaded['netman.providers.container'] = nil
            package.loaded['netman.tools.shell'] = nil
        end)
        after_each(function()
            package.loaded['netman.tools.shell'] = nil
        end)

        local function make_container_with_shell(run_fn)
            package.loaded['netman.tools.shell'] = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function() return { run = run_fn, dump_self_to_table = function() return {} end } end
            }
            package.loaded['netman.providers.container'] = nil
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            return container_mod:new("podman", "somecontainer", cache), container_mod
        end

        it("should return ERROR on non-0 exit code", function()
            local container, container_mod = make_container_with_shell(function()
                return { stderr = "we dun failed", exit_code = 1, stdout = {"STATUS"} }
            end)
            assert.is_equal(container_mod.CONSTANTS.STATUS.ERROR, container:current_status())
        end)

        it("should return INVALID on nonexistent container", function()
            local container, container_mod = make_container_with_shell(function()
                return { stderr = "", exit_code = 0, stdout = {"STATUS"} }
            end)
            assert.is_equal(container_mod.CONSTANTS.STATUS.INVALID, container:current_status())
        end)

        it("should return NOT RUNNING on stopped container", function()
            local container, container_mod = make_container_with_shell(function()
                return { stderr = "", exit_code = 0, stdout = {"STATUS", "Exited (0) 2 hours ago"} }
            end)
            assert.is_equal(container_mod.CONSTANTS.STATUS.NOT_RUNNING, container:current_status())
        end)

        it("should return RUNNING on running container", function()
            local container, container_mod = make_container_with_shell(function()
                return { stderr = "", exit_code = 0, stdout = {"STATUS", "Up 2 hours"} }
            end)
            assert.is_equal(container_mod.CONSTANTS.STATUS.RUNNING, container:current_status())
        end)
    end)

    describe("#start", function()
        before_each(function()
            package.loaded['netman.providers.container'] = nil
            package.loaded['netman.tools.shell'] = nil
        end)
        after_each(function()
            package.loaded['netman.tools.shell'] = nil
        end)

        local function make_container(run_fn, status)
            package.loaded['netman.tools.shell'] = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function(_, cmd, opts)
                    return {
                        run = function()
                            local result = run_fn()
                            if opts and opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK] then
                                opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK](result)
                            end
                            return result
                        end,
                        dump_self_to_table = function() return {} end
                    }
                end
            }
            package.loaded['netman.providers.container'] = nil
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.current_status = function() return status end
            return container, container_mod
        end

        it("should return success=false if start returns non-0", function()
            local container, _ = make_container(function() return {stderr = "nope", exit_code = 1, stdout = {""}} end, "NOT RUNNING")
            local result = container:start()
            assert.is_false(result.success)
        end)

        it("should return success=true when container is running after start", function()
            local statuses = {"NOT RUNNING", "RUNNING"}
            local i = 0
            local container, _ = make_container(function() return {stderr = "", exit_code = 0, stdout = {""}} end, nil)
            container.current_status = function() i = i + 1; return statuses[i] or "RUNNING" end
            local result = container:start()
            assert.is_true(result.success)
        end)

        it("should return success=false when container is still not running after start", function()
            local container, _ = make_container(function() return {stderr = "", exit_code = 0, stdout = {""}} end, "NOT RUNNING")
            local result = container:start()
            assert.is_false(result.success)
        end)
    end)

    describe("#put", function()
        local _fs_stat

        before_each(function()
            package.loaded['netman.providers.container'] = nil
            package.loaded['netman.tools.shell'] = nil
            _fs_stat = vim.loop.fs_stat
        end)
        after_each(function()
            vim.loop.fs_stat = _fs_stat
            package.loaded['netman.tools.shell'] = nil
        end)

        it("should return success=false when cp command fails", function()
            package.loaded['netman.tools.shell'] = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function(_, cmd, opts)
                    return {
                        run = function()
                            local result = { exit_code = 1, stderr = "cp failed", stdout = "" }
                            if opts and opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK] then
                                opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK](result)
                            end
                            return result
                        end
                    }
                end
            }
            package.loaded['netman.providers.container'] = nil
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.mkdir = function() return { success = true } end
            container.stat = function() return { ['/tmp/remotefile'] = {} } end
            container_mod.stat = function() return { ['/tmp/remotefile'] = {} } end
            vim.loop.fs_stat = function() return { type = 'file' } end
            local result = container:put("/tmp/localfile", "podman://somecontainer///tmp/remotefile", {})
            assert.is_false(result.success)
        end)

        it("should return success=true when cp command succeeds", function()
            package.loaded['netman.tools.shell'] = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function(_, cmd, opts)
                    return {
                        run = function()
                            local result = { exit_code = 0, stderr = "", stdout = "" }
                            if opts and opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK] then
                                opts[SHELL_CONSTANTS.FLAGS.EXIT_CALLBACK](result)
                            end
                            return result
                        end
                    }
                end
            }
            package.loaded['netman.providers.container'] = nil
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.mkdir = function() return { success = true } end
            container.stat = function() return { ['/tmp/remotefile'] = {} } end
            container_mod.stat = function() return { ['/tmp/remotefile'] = {} } end
            vim.loop.fs_stat = function() return { type = 'file' } end
            local result = container:put("/tmp/localfile", "podman://somecontainer///tmp/remotefile", {})
            assert.is_true(result.success)
        end)
    end)

    describe("#mkdir", function()
        before_each(function()
            package.loaded['netman.providers.container'] = nil
        end)
        after_each(function()
            package.loaded['netman.providers.container'] = nil
        end)

        it("should return success=false on non-0 exit code", function()
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.run_command = function() return { exit_code = 1, stderr = "mkdir failed", stdout = "" } end
            local result = container:mkdir("/tmp/somepath")
            assert.is_false(result.success)
        end)

        it("should return success=true on 0 exit code", function()
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.run_command = function() return { exit_code = 0, stderr = "", stdout = "" } end
            local result = container:mkdir("/tmp/somepath")
            assert.is_true(result.success)
        end)
    end)
end)
