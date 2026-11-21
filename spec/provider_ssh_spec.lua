_G._QUIET = true -- This makes bootstrap shut up
vim.g.netman_log_level = 0
local SHELL_CONSTANTS = require("netman.tools.shell").CONSTANTS

local describe = require('busted').describe
local it = require('busted').it
local before_each = require("busted").before_each
local after_each = require("busted").after_each

describe("Netman Provider #ssh", function()
    describe("#init", function()
        before_each(function ()
            package.loaded['netman.providers.ssh'] = nil
        end)
        after_each(function ()
            package.loaded['netman.tools.shell'] = nil
        end)
        it("should complain if ssh isn't available for use", function()
            local utils = require("netman.tools.utils")
            local orig_os_has = utils.os_has
            utils.os_has = function() return false end
            local config = { get = function() return {} end, set = function() end, save = function() end }
            local ok = require("netman.providers.ssh").init(config)
            utils.os_has = orig_os_has
            assert.is_false(ok, "SSH failed to fail on failure to find ssh in path")
        end)
        it("should be happy if ssh is available for use", function ()
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
            local config = { get = function() return {} end, set = function() end, save = function() end }
            assert.is_true(require("netman.providers.ssh").init(config), "SSH failed to accept that ssh was found")
        end)
    end)

    describe("#URI", function()
        local cache
        before_each(function()
            cache = require("netman.tools.cache"):new()
            package.loaded['netman.providers.ssh'] = nil
        end)
        after_each(function()
            cache:clear()
        end)

        it("should fail if no protocol is provided", function()
            assert.has_error(function()
                require("netman.providers.ssh").internal.URI:new("://somehost/somepath", cache)
            end)
        end)
        it("should fail if an invalid protocol is provided", function()
            assert.has_error(function()
                require("netman.providers.ssh").internal.URI:new("someprotocol://somehost/somepath", cache)
            end)
        end)
        it("should fail on invalid host provided", function()
            assert.has_error(function()
                require("netman.providers.ssh").internal.URI:new("sftp:///somepath/", cache)
            end)
            assert.has_error(function()
                require("netman.providers.ssh").internal.URI:new("sftp:///somepath/somefile.txt", cache)
            end)
        end)
        it("should normalize extra slashes in path", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost////somepath/somefile.txt", cache)
            assert.is_equal("/somepath/somefile.txt", uri:to_string())
        end)
        it("should not find a username", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost///somepath/somefile.txt", cache)
            assert.is_equal('', uri.user)
        end)
        it("should find a username", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://someuser@somehost///somepath/somefile.txt", cache)
            assert.is_equal('someuser', uri.user)
        end)
        it("should not find a port", function ()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost///somepath/somefile.txt", cache)
            assert.is_equal('', uri.port)
        end)
        it("should find a port", function ()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost:1111/somepath/somefile.txt", cache)
            assert.is_equal('1111', uri.port)
        end)
        it("should find an absolute path", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost///somepath/somefile.txt", cache)
            assert.is_equal("/somepath/somefile.txt", uri:to_string())
            assert.is_false(uri.is_relative)
        end)
        it("should find a relative path", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost/somepath/somefile.txt", cache)
            assert.is_equal("~/somepath/somefile.txt", uri:to_string())
            assert.is_true(uri.is_relative)
        end)
        it("should find the user", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://someuser@somehost/", cache)
            assert.is_equal("someuser", uri.user)
        end)
        it("should find the port", function()
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost:1111/", cache)
            assert.is_equal("1111", uri.port)
        end)
        it('should identify a "link" (directory)', function()
            local api = require("netman.tools.options").api
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost/", cache)
            assert.is_equal(api.ATTRIBUTES.DIRECTORY, uri.type)
            assert.is_equal(api.READ_TYPE.EXPLORE, uri.return_type)
        end)
        it('should identify a "destination" (file")', function ()
            local api = require("netman.tools.options").api
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost/somefile.txt", cache)
            assert.is_equal(api.ATTRIBUTES.FILE, uri.type)
            assert.is_equal(api.READ_TYPE.FILE, uri.return_type)
        end)
        it("should get the parent directory correct", function()
            local api = require("netman.tools.options").api
            local uri = require("netman.providers.ssh").internal.URI:new("sftp://somehost///a/b/c.txt", cache)
            local parent = uri:parent()
            assert.is_equal("ssh://somehost///a/b/", parent:to_string('remote'))
            assert.is_equal(api.ATTRIBUTES.DIRECTORY, parent.type)
            assert.is_equal("/a/b", parent.__path_as_string)
        end)
        it("should generate a proper auth uri", function ()
            local ssh = require("netman.providers.ssh").internal
            local uri1 = ssh.URI:new("sftp://somehost/", cache)
            local uri2 = ssh.URI:new("sftp://somehost:1111/", cache)
            local uri3 = ssh.URI:new("sftp://user@somehost/", cache)
            assert.is_truthy(uri1.auth_uri:match("somehost"))
            assert.is_truthy(uri2.auth_uri:match("somehost"))
            assert.is_truthy(uri2.auth_uri:match("1111"))
            assert.is_truthy(uri3.auth_uri:match("user@somehost"))
        end)
    end)

    describe("#find", function()
        it("should return stdout from run_command on success", function()
            local ssh = require("netman.providers.ssh").internal.SSH
            local host = {
                run_command = function(_, cmd, _)
                    assert.is_truthy(cmd:match("^find /tmp"))
                    return { exit_code = 0, stdout = "/tmp/a\n/tmp/b\n", stderr = "" }
                end
            }
            local result = ssh.find(host, "/tmp")
            assert.is_equal("/tmp/a\n/tmp/b\n", result)
        end)
        it("should return error details on non-zero exit code", function()
            local ssh = require("netman.providers.ssh").internal.SSH
            local host = {
                run_command = function()
                    return { exit_code = 1, stdout = "", stderr = "find failed" }
                end
            }
            local result = ssh.find(host, "/tmp")
            assert.is_equal("find failed", result.error)
        end)
        it("should pass async option through to run_command", function()
            local ssh = require("netman.providers.ssh").internal.SSH
            local handle = { id = "handle" }
            local host = {
                run_command = function(_, _, opts)
                    return opts[require("netman.tools.shell").CONSTANTS.FLAGS.ASYNC] and handle or { exit_code = 0, stdout = "" }
                end
            }
            local result = ssh.find(host, "/tmp", { async = true })
            assert.are.same(handle, result)
        end)
    end)

    describe("#validate", function()
        local cache
        before_each(function()
            cache = require("netman.tools.cache"):new()
            package.loaded['netman.providers.ssh'] = nil
        end)
        after_each(function()
            cache:clear()
        end)
        it("should assert if no cache is provided", function()
            local ssh = require("netman.providers.ssh")
            assert.has_error(function()
                ssh.internal.validate("ssh://host///file", nil)
            end)
        end)
        it("should return uri and host for a valid uri", function()
            local ssh = require("netman.providers.ssh")
            local orig_new = ssh.internal.SSH.new
            local fake_host = { host = "host" }
            ssh.internal.SSH.new = function() return fake_host end
            local result = ssh.internal.validate("ssh://host///file", cache)
            ssh.internal.SSH.new = orig_new
            assert.is_not_nil(result.uri)
            assert.are.equal(fake_host, result.host)
        end)
    end)

    describe("#read_file", function()
        before_each(function()
            package.loaded['netman.providers.ssh'] = nil
        end)
        it("should return file read data on successful get", function()
            local ssh = require("netman.providers.ssh")
            local uri = {
                unique_name = "localfile",
                to_string = function() return "ssh://host///remotefile" end
            }
            local host = {
                get = function(_, _, _, opts)
                    assert.is_equal("localfile", opts.new_file_name)
                    return { success = true }
                end
            }
            local result = ssh.internal.read_file(uri, host)
            assert.is_true(result.success)
            assert.is_not_nil(result.data.local_path)
        end)
        it("should return permission error on permission denied", function()
            local ssh = require("netman.providers.ssh")
            local uri = {
                unique_name = "localfile",
                to_string = function() return "ssh://host///remotefile" end
            }
            local host = {
                get = function()
                    return { success = false, error = "Permission denied" }
                end
            }
            local result = ssh.internal.read_file(uri, host)
            assert.is_false(result.success)
            assert.is_equal(require("netman.tools.options").api.ERRORS.PERMISSION_ERROR, result.message.error)
        end)
        it("should return async handle when callback is provided", function()
            local ssh = require("netman.providers.ssh")
            local uri = {
                unique_name = "localfile",
                to_string = function() return "ssh://host///remotefile" end
            }
            local handle = { id = "handle" }
            local host = {
                get = function(_, _, _, opts)
                    assert.is_true(opts.async)
                    return handle
                end
            }
            local result = ssh.internal.read_file(uri, host, function() end)
            assert.are.same(handle, result.handle)
        end)
    end)

    describe("#read_directory", function() end)
    describe("#write_file", function() end)
    describe("#create_directory", function() end)
end)
