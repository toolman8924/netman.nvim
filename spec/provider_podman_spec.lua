_G._QUIET = true -- This makes bootstrap shut up
vim.g.netman_log_level = 0
local SHELL_CONSTANTS = require("netman.tools.shell").CONSTANTS

local describe = require("busted").describe
local it = require("busted").it
local before_each = require("busted").before_each
local after_each = require("busted").after_each

describe("Netman Provider #podman", function()
    describe("#init", function()
        before_each(function ()
            package.loaded['netman.providers.podman'] = nil
        end)
        after_each(function ()
            package.loaded['netman.tools.shell'] = nil
        end)
        it("should complain if podman isn't available for use", function()
            local shell = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function() return
                    {
                        run = function()
                            return {
                                stderr = "SUPER DUPER MEGA ERR",
                                exit_code = 9001,
                                stdout = "MUH DED"
                            }
                        end
                    }
                end
            }
            package.loaded['netman.tools.shell'] = shell
            assert.is_false(require("netman.providers.podman").init(), "Podman failed to fail on failure to find podman in path")
        end)
        it("should be happy if podman is available for use", function ()
             local shell = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function() return
                    {
                        run = function()
                            return {
                                stderr = "",
                                exit_code = 0,
                                stdout = ""
                            }
                        end
                    }
                end
            }
            package.loaded['netman.tools.shell'] = shell
            assert.is_true(require("netman.providers.podman").init(), "Podman failed to accept that podman was found")
        end)
    end)
    describe("#read_file", function()
        before_each(function()
            package.loaded['netman.tools.shell'] = nil
            package.loaded['netman.providers.podman'] = nil
        end)
        it("should return error details when container.get fails", function()
            local uri = {
                unique_name = 'somelocalfile',
                to_string = function() return 'podman://somecontainer///someremotefile' end
            }
            local container = {
                get = function(_, _, _)
                    return { success = false, error = 'exit code 1' }
                end
            }
            local result = require("netman.providers.podman").internal.read_file(uri, container)
            assert.is_false(result.success, "Podman read_file should not succeed on container.get failure")
            assert.is_not_nil(result.error, "Podman read_file should surface container.get error")
        end)
        it("should return file read data on successful container.get", function()
            local uri = {
                unique_name = 'somelocalfile',
                to_string = function() return 'podman://somecontainer///someremotefile' end
            }
            local container = {
                get = function(_, _, _, opts)
                    assert.is_equal('somelocalfile', opts.new_file_name)
                    return { success = true }
                end
            }
            local result = require("netman.providers.podman").internal.read_file(uri, container)
            local api = require("netman.tools.options").api
            assert.is_true(result.success, "Podman read_file should succeed on successful container.get")
            assert.is_equal(api.READ_TYPE.FILE, result.type, "Podman read_file should return FILE read type")
            assert.is_truthy(result.data.local_path:match('somelocalfile$'), "Podman read_file should return local_path ending with unique_name")
            assert.is_equal('podman://somecontainer///someremotefile', result.data.origin_path, "Podman read_file should return origin_path")
        end)
    end)
    describe("#read_directory", function()
        before_each(function()
            package.loaded['netman.providers.podman'] = nil
        end)

        it("should return EXPLORE data on successful find", function()
            local uri = { to_string = function() return "podman://somecontainer///somepath/" end }
            local podman = require("netman.providers.podman")
            local original_find = podman.internal.find
            podman.internal.find = function()
                return {
                    success = true,
                    data = {
                        ["podman://somecontainer///somepath/file.txt"] = {
                            URI = "podman://somecontainer///somepath/file.txt",
                            FIELD_TYPE = "DESTINATION",
                            NAME = "file.txt",
                            ABSOLUTE_PATH = "/somepath/file.txt",
                        }
                    }
                }
            end
            local result = podman.internal.read_directory(uri, {})
            podman.internal.find = original_find
            local api = require("netman.tools.options").api
            assert.is_true(result.success)
            assert.is_equal(api.READ_TYPE.EXPLORE, result.type)
            assert.is_not_nil(result.data["podman://somecontainer///somepath/file.txt"])
        end)

        it("should return success=false when find fails", function()
            local uri = { to_string = function() return "podman://somecontainer///somepath/" end }
            local podman = require("netman.providers.podman")
            local original_find = podman.internal.find
            podman.internal.find = function() return { success = false, message = "permission denied" } end
            local result = podman.internal.read_directory(uri, {})
            podman.internal.find = original_find
            assert.is_false(result.success)
            assert.is_not_nil(result.message)
        end)
    end)
    describe("#validate", function()
        local original_new_container
        local original_shell

        before_each(function()
            package.loaded['netman.providers.podman'] = nil
            package.loaded['netman.providers.container'] = nil
            package.loaded['netman.tools.cache'] = nil
            original_shell = package.loaded['netman.tools.shell']
            local container = require("netman.providers.container")
            original_new_container = container.new
        end)

        after_each(function()
            if original_new_container then
                require("netman.providers.container").new = original_new_container
            end
            package.loaded['netman.tools.shell'] = original_shell
            package.loaded['netman.providers.podman'] = nil
            package.loaded['netman.providers.container'] = nil
        end)

        it("should return uri and container when container is RUNNING", function()
            local cache = require("netman.tools.cache"):new()
            local container_mod = require("netman.providers.container")
            local fake_container = {
                name = 'somecontainer',
                current_status = function() return container_mod.CONSTANTS.STATUS.RUNNING end
            }
            container_mod.new = function() return fake_container end

            local result = require("netman.providers.podman").internal.validate("podman://somecontainer///somepath", cache)
            assert.is_not_nil(result.uri, "validate did not return parsed uri")
            assert.is_equal(fake_container, result.container, "validate did not return container")
            assert.is_nil(result.message, "validate should not return message for running container")
        end)

        it("should short circuit container status when cache reports RUNNING", function()
            package.loaded['netman.tools.shell'] = {
                CONSTANTS = SHELL_CONSTANTS,
                new = function() error("shell should not be called when status is cached RUNNING") end
            }
            package.loaded['netman.providers.container'] = nil
            local container_mod = require("netman.providers.container")
            local cache = require("netman.tools.cache"):new()
            local container = container_mod:new("podman", "somecontainer", cache)
            container.cache:add_item('status', 'RUNNING')
            assert.is_equal(container_mod.CONSTANTS.STATUS.RUNNING, container:current_status(), "Container did not use cached RUNNING status")
        end)

        it("should return a start prompt message when container is not RUNNING", function()
            local cache = require("netman.tools.cache"):new()
            local container_mod = require("netman.providers.container")
            local start_called = false
            local fake_container = {
                name = 'somecontainer',
                current_status = function() return container_mod.CONSTANTS.STATUS.NOT_RUNNING end,
                start = function() start_called = true; return { success = true } end
            }
            container_mod.new = function() return fake_container end

            local result = require("netman.providers.podman").internal.validate("podman://somecontainer///somepath", cache)
            assert.is_not_nil(result.message, "validate did not return prompt message for stopped container")
            assert.is_equal('Y', result.message.default, "validate prompt default should be Y")
            assert.is_function(result.message.callback, "validate prompt callback missing")

            local ok = result.message.callback('Y')
            assert.is_true(ok, "validate callback should return true when container starts")
            assert.is_true(start_called, "validate callback did not start container")
        end)

        it("should not start container when user declines prompt", function()
            local cache = require("netman.tools.cache"):new()
            local container_mod = require("netman.providers.container")
            local start_called = false
            local fake_container = {
                name = 'somecontainer',
                current_status = function() return container_mod.CONSTANTS.STATUS.INVALID end,
                start = function() start_called = true; return { success = true } end
            }
            container_mod.new = function() return fake_container end

            local result = require("netman.providers.podman").internal.validate("podman://somecontainer///somepath", cache)
            local ok = result.message.callback('n')
            assert.is_false(ok, "validate callback should return false when user declines")
            assert.is_false(start_called, "container should not start when user declines")
        end)
    end)
end)
