_G._QUIET = true -- This makes bootstrap shut up
vim.g.netman_log_level = 0
local SHELL_CONSTANTS = require("netman.tools.shell").CONSTANTS

local spy = require("luassert.spy")
local describe = require('busted').describe
local it = require('busted').it
local before_each = require("busted").before_each
local after_each = require("busted").after_each
local pending = require("busted").pending

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
        pending("should get the parent directory correct")
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
        pending("should properly read a valid find result from a file")
        pending("should properly read a valid find result from an empty file")
        pending("should properly read a valid find result from a directory")
        pending("should properly read a valid find result with absolute path name")
    end)

    describe("#validate", function()
        pending("should quick escape if there is already a cached result for the uri provided")
        pending("should not do anything if there is an invalid uri")
        pending("should create the cache for the uri")
    end)

    describe("#read_file", function()
        pending("should complain if you aren't using sftp or scp protocol")
        pending("should include the port in the generated command")
        pending("should properly handle relative pathing")
        pending("should properly handle absolute pathing")
        pending("should complain if a non-0 exit code is provided")
        pending("should prompt to create missing file #debug")
        pending("should create the missing file #debug")
        pending("should not create the missing file #debug")
    end)

    describe("#read_directory", function() end)
    describe("#write_file", function() end)
    describe("#create_directory", function() end)
end)
