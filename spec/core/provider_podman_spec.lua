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
    describe("#_parse_uri", function()
        -- WARN: Missing Failure Conditions!
        after_each(function()
            package.loaded['netman.providers.podman'] = nil
        end)
        it("should return a proper table for a file in a container", function()
            local protocol = "podman"
            local container = "somecontainer"
            local parent = "/somepath/"
            local path = parent .. "somefile.txt"
            local uri = string.format("%s://%s%s", protocol, container, path)
            local parsed_uri = require("netman.providers.podman").internal._parse_uri(uri)
            assert.is_equal(parsed_uri.base_uri, uri, "Podman did not properly store the provided URI")
            assert.is_equal(parsed_uri.protocol, protocol, "Podman did not properly parse the protocol from the URI")
            assert.is_equal(parsed_uri.container, container, "Podman did not properly parse the container from the URI")
            assert.is_equal(parsed_uri.path, path, "Podman did not properly parse the path from the URI")
            assert.is_equal(parsed_uri.file_type, require("netman.tools.options").api.ATTRIBUTES.FILE, "Podman did not properly parse the file type from the URI")
            assert.is_equal(parsed_uri.return_type, require("netman.tools.options").api.READ_TYPE.FILE, "Podman did not properly set the return type of the URI")
            assert.is_equal(parsed_uri.parent, parent, "Podman did not properly find the parent of the file")
            assert.is_not_nil(parsed_uri.local_file, "Podman did not set a local location for the file to be pulled to")
        end)
        it("should return a proper table for a directory in a container", function()
            local protocol = "podman"
            local container = "somecontainer"
            local parent = "/somepath/"
            local path = parent .. "somechildpath/"
            local uri = string.format("%s://%s%s", protocol, container, path)
            local parsed_uri = require("netman.providers.podman").internal._parse_uri(uri)
            assert.is_equal(parsed_uri.base_uri, uri, "Podman did not properly store the provided URI")
            assert.is_equal(parsed_uri.protocol, protocol, "Podman did not properly parse the protocol from the URI")
            assert.is_equal(parsed_uri.container, container, "Podman did not properly parse the container from the URI")
            assert.is_equal(parsed_uri.path, path, "Podman did not properly parse the path from the URI")
            assert.is_equal(parsed_uri.file_type, require("netman.tools.options").api.ATTRIBUTES.DIRECTORY, "Podman did not properly parse the file type from the URI")
            assert.is_equal(parsed_uri.return_type, require("netman.tools.options").api.READ_TYPE.EXPLORE, "Podman did not properly set the return type of the URI")
            assert.is_equal(parsed_uri.parent, parent, "Podman did not properly find the parent of the file")
            assert.is_nil(parsed_uri.local_file, "Podman did not set a local location for the file to be pulled to")
        end)
        it("should fail to generate a proper table due to bad path", function()
            local uri = "podman://somecontainer///somepath/somefile.txt"
            local parsed_uri = require("netman.providers.podman").internal._parse_uri(uri)
            assert.is_nil(next(parsed_uri), "Podman did not properly fail to parse invalid uri")
        end)
    end)
    describe("#_process_find_results", function()
        it("should properly read a valid find result from a file", function()
            local mode = "81ed"
            local blocks = '0'
            local blksize = '512'
            local mtime_sec = '1662860937'
            local user = 'root'
            local group = 'root'
            local inode = '1092025921'
            local permissions = '755'
            local size = '0'
            local type = 'regular file'
            local name = 'somefilename'
            local input_result = string.format("MODE=%s,BLOCKS=%s,BLKSIZE=%s,MTIME_SEC=%s,USER=%s,GROUP=%s,INODE=%s,PERMISSIONS=%s,SIZE=%s,TYPE=%s,NAME=%s", mode, blocks, blksize, mtime_sec, user, group, inode, permissions, size, type, name)
            local result = require("netman.providers.podman").internal._process_find_result(input_result)
            assert.is_equal(result.TYPE, 'file', "Podman failed to properly identify file type")
            assert.is_equal(result.FIELD_TYPE, require("netman.tools.options").explorer.METADATA.DESTINATION, "Podman failed to properly identify field type")
            assert.is_equal(result.NAME, name, "Podman failed to properly identify file name")
            assert.is_equal(result.ABSOLUTE_PATH, name, "Podman failed to properly identify path to file")
            assert.is_equal(result.MODE, mode, "Podman failed to properly identify mode of file")
            assert.is_equal(result.BLOCKS, blocks, "Podman failed to properly identify blocks of file")
            assert.is_equal(result.BLKSIZE, blksize, "Podman failed to properly identify block size of file")
            assert.is_equal(result.MTIME_SEC, mtime_sec, "Podman failed to properly identify mtime seconds of file")
            assert.is_equal(result.USER, user, "Podman failed to properly identify the owner of file")
            assert.is_equal(result.GROUP, group, "Podman failed to properly identify the owning group of file")
            assert.is_equal(result.INODE, inode, "Podman failed to fine file's inode")
            assert.is_equal(result.PERMISSIONS, permissions, "Podman failed to identify file's permissions")
            assert.is_equal(result.SIZE, size, "Podman failed to identify size of file")
        end)
        it("should properly read a valid find result from an empty file", function()
            local mode = "81ed"
            local blocks = '0'
            local blksize = '512'
            local mtime_sec = '1662860937'
            local user = 'root'
            local group = 'root'
            local inode = '1092025921'
            local permissions = '755'
            local size = '0'
            local type = 'regular empty file'
            local name = 'somefilename'
            local input_result = string.format("MODE=%s,BLOCKS=%s,BLKSIZE=%s,MTIME_SEC=%s,USER=%s,GROUP=%s,INODE=%s,PERMISSIONS=%s,SIZE=%s,TYPE=%s,NAME=%s", mode, blocks, blksize, mtime_sec, user, group, inode, permissions, size, type, name)
            local result = require("netman.providers.podman").internal._process_find_result(input_result)
            assert.is_equal(result.TYPE, 'file', "Podman failed to properly identify file type")
            assert.is_equal(result.FIELD_TYPE, require("netman.tools.options").explorer.METADATA.DESTINATION, "Podman failed to properly identify field type")
            assert.is_equal(result.NAME, name, "Podman failed to properly identify file name")
            assert.is_equal(result.ABSOLUTE_PATH, name, "Podman failed to properly identify path to file")
            assert.is_equal(result.MODE, mode, "Podman failed to properly identify mode of file")
            assert.is_equal(result.BLOCKS, blocks, "Podman failed to properly identify blocks of file")
            assert.is_equal(result.BLKSIZE, blksize, "Podman failed to properly identify block size of file")
            assert.is_equal(result.MTIME_SEC, mtime_sec, "Podman failed to properly identify mtime seconds of file")
            assert.is_equal(result.USER, user, "Podman failed to properly identify the owner of file")
            assert.is_equal(result.GROUP, group, "Podman failed to properly identify the owning group of file")
            assert.is_equal(result.INODE, inode, "Podman failed to fine file's inode")
            assert.is_equal(result.PERMISSIONS, permissions, "Podman failed to identify file's permissions")
            assert.is_equal(result.SIZE, size, "Podman failed to identify size of file")
        end)
        it("should properly read a valid find result from a directory", function()
            local mode = "81ed"
            local blocks = '0'
            local blksize = '512'
            local mtime_sec = '1662860937'
            local user = 'root'
            local group = 'root'
            local inode = '1092025921'
            local permissions = '755'
            local size = '0'
            local type = 'directory'
            local name = 'somefilename'
            local input_result = string.format("MODE=%s,BLOCKS=%s,BLKSIZE=%s,MTIME_SEC=%s,USER=%s,GROUP=%s,INODE=%s,PERMISSIONS=%s,SIZE=%s,TYPE=%s,NAME=%s", mode, blocks, blksize, mtime_sec, user, group, inode, permissions, size, type, name)
            local result = require("netman.providers.podman").internal._process_find_result(input_result)
            assert.is_equal(result.TYPE, 'directory', "Podman failed to properly identify file type")
            assert.is_equal(result.FIELD_TYPE, require("netman.tools.options").explorer.METADATA.LINK, "Podman failed to properly identify field type")
            assert.is_equal(result.NAME, name, "Podman failed to properly identify file name")
            assert.is_equal(result.ABSOLUTE_PATH, name, "Podman failed to properly identify path to file")
            assert.is_equal(result.MODE, mode, "Podman failed to properly identify mode of file")
            assert.is_equal(result.BLOCKS, blocks, "Podman failed to properly identify blocks of file")
            assert.is_equal(result.BLKSIZE, blksize, "Podman failed to properly identify block size of file")
            assert.is_equal(result.MTIME_SEC, mtime_sec, "Podman failed to properly identify mtime seconds of file")
            assert.is_equal(result.USER, user, "Podman failed to properly identify the owner of file")
            assert.is_equal(result.GROUP, group, "Podman failed to properly identify the owning group of file")
            assert.is_equal(result.INODE, inode, "Podman failed to fine file's inode")
            assert.is_equal(result.PERMISSIONS, permissions, "Podman failed to identify file's permissions")
            assert.is_equal(result.SIZE, size, "Podman failed to identify size of file")
        end)
        it("should properly read a valid find result with absolute path name", function()
            local mode = "81ed"
            local blocks = '0'
            local blksize = '512'
            local mtime_sec = '1662860937'
            local user = 'root'
            local group = 'root'
            local inode = '1092025921'
            local permissions = '755'
            local size = '0'
            local type = 'directory'
            local name = 'somefilename'
            local path = string.format("/somepath/%s", name)
            local input_result = string.format("MODE=%s,BLOCKS=%s,BLKSIZE=%s,MTIME_SEC=%s,USER=%s,GROUP=%s,INODE=%s,PERMISSIONS=%s,SIZE=%s,TYPE=%s,NAME=%s", mode, blocks, blksize, mtime_sec, user, group, inode, permissions, size, type, path)
            local result = require("netman.providers.podman").internal._process_find_result(input_result)
            assert.is_equal(result.TYPE, 'directory', "Podman failed to properly identify file type")
            assert.is_equal(result.FIELD_TYPE, require("netman.tools.options").explorer.METADATA.LINK, "Podman failed to properly identify field type")
            assert.is_equal(result.NAME, name, "Podman failed to properly identify file name")
            assert.is_equal(result.ABSOLUTE_PATH, path, "Podman failed to properly identify path to file")
            assert.is_equal(result.MODE, mode, "Podman failed to properly identify mode of file")
            assert.is_equal(result.BLOCKS, blocks, "Podman failed to properly identify blocks of file")
            assert.is_equal(result.BLKSIZE, blksize, "Podman failed to properly identify block size of file")
            assert.is_equal(result.MTIME_SEC, mtime_sec, "Podman failed to properly identify mtime seconds of file")
            assert.is_equal(result.USER, user, "Podman failed to properly identify the owner of file")
            assert.is_equal(result.GROUP, group, "Podman failed to properly identify the owning group of file")
            assert.is_equal(result.INODE, inode, "Podman failed to fine file's inode")
            assert.is_equal(result.PERMISSIONS, permissions, "Podman failed to identify file's permissions")
            assert.is_equal(result.SIZE, size, "Podman failed to identify size of file")
        end)
    end)
    describe("#_validate_cache", function()
        local cache = require("netman.tools.cache"):new()
        local input = nil
        before_each(function()
            cache:clear()
            input = {
                container = "somecontainer",
                path = "somepath"
            }
            package.loaded['netman.providers.podman'] = nil
        end)
        after_each(function()
            cache:clear()
        end)

        it("should add missing items to the container cache", function()
            require("netman.providers.podman").internal._validate_cache(cache, input)
            assert.is_not_nil(cache:get_item(input.container), "Podman did not add a new item to the provided cache for the container")
            assert.is_not_nil(cache:get_item(input.container):get_item('files'), 'Podman did not add a files cache')
            assert.is_not_nil(cache:get_item(input.container):get_item('file_metadata'), 'Podman did not add a metadata_cache')
        end)
        it("should not override existing cache items for the container", function()
            local container_cache = require("netman.tools.cache"):new()
            local files_cache = require("netman.tools.cache"):new()
            local metadata_cache = require("netman.tools.cache"):new()
            cache:add_item(input.container, container_cache)
            cache:add_item('files', files_cache)
            cache:add_item('file_metadata', metadata_cache)
            require("netman.providers.podman").internal._validate_cache(cache, input)
            assert.is_equal(cache:get_item(input.container), container_cache, "Podman overrode the existing container cache")
            assert.is_equal(cache:get_item('files'), files_cache, "Podman overrode the existing container files cache")
            assert.is_equal(cache:get_item('file_metadata'), metadata_cache, "Podman overrode the existing metadata cache")
        end)
    end)
    describe("#_is_container_running", function()
        before_each(function()
            package.loaded['netman.providers.podman'] = nil
        end)
        after_each(function()
            package.loaded['netman.tools.shell'] = nil
        end)
        it("should complain on podman non-0 exit code", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 1, stdout = "we dun failed"} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_equal('ERROR', require("netman.providers.podman").internal._is_container_running('somecontainer'), "Podman failed to fail properly")
        end)
        it("should return invalid on nonexistent container", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = {"STATUS"}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_equal('INVALID', require("netman.providers.podman").internal._is_container_running('somecontainer'), "Podman failed register container search as invalid")
        end)
        it("should return not running on not running container", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = {"STATUS", ""}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_equal('NOT_RUNNING', require("netman.providers.podman").internal._is_container_running('somecontainer'), "Podman failed register container as not running")
        end)
        it("should return running on valid running container", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = {"STATUS", 'Up 2 hours'}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_equal('RUNNING', require("netman.providers.podman").internal._is_container_running('somecontainer'), "Podman failed register container as running")
        end)
    end)
    describe("#_start_container", function()
        before_each(function()
            package.loaded['netman.tools.shell'] = nil
            package.loaded['netman.providers.podman'] = nil
        end)
        it("should return false if an exit code is returned by podman", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 1, stdout = {""}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_false(require("netman.providers.podman").internal._start_container("somecontainer"), "Podman failed to fail on startup properly")
        end)
        it("should return true if podman was able to start the requested container", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = {""}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            require("netman.providers.podman").internal._is_container_running = function(...) return 'RUNNING' end
            assert.is_true(require("netman.providers.podman").internal._start_container("somecontainer"), "Podman failed to start container properly")
        end)
        it("should return true if podman was able to start the requested container", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = {""}} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            require("netman.providers.podman").internal._is_container_running = function(...) return 'NOT VALID' end
            assert.is_false(require("netman.providers.podman").internal._start_container("somecontainer"), "Podman failed to handle weird container startup state properly")
        end)
    end)
    describe("#_read_file", function()
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
                get = function(_, _, opts)
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
    describe("#_read_directory", function()
        -- This function should be a thin wrapper around `_process_find_result` and thus there shouldn't be
        -- a ton that needs tested
        before_each(function()
            package.loaded['netman.providers.podman'] = nil
            package.loaded['netman.tools.shell'] = nil
        end)
        it("should return cached results if they are present", function()
            local cache = require("netman.tools.cache"):new()
            local _ = require("netman.tools.cache"):new()
            local file_cache = require("netman.tools.cache"):new()
            file_cache:add_item("somepath", "somefile")
            _:add_item('someuri', file_cache)
            cache:add_item('files', _)
            local cached_results = require("netman.providers.podman").internal._read_directory("someuri", "somepath", "somecontainer", cache)
            assert.is_not_nil(cached_results, "Podman failed to return cached results")
            assert.is_not_nil(cached_results.remote_files, "Podman failed to return cached results")
            assert.is_equal(cached_results.remote_files.hello, file_cache:as_table().hello, "Podman failed to the correct cached results")
        end)
        it("should bail out on received exit code", function()
            local cache = require("netman.tools.cache"):new()
            cache:add_item('files', require("netman.tools.cache"):new())
            cache:add_item('file_metadata', require("netman.tools.cache"):new())
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 1, stdout = ""} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_nil(require("netman.providers.podman").internal._read_directory("someuri", "somepath", "somecontainer", cache), "Podman failed to bail on exit code from reading directory")
        end)
    end)
    describe("#_write_file", function()
        local _fs_open = vim.loop.fs_open
        local _fs_write = vim.loop.fs_write
        local _fs_close = vim.loop.fs_close
        before_each(function()
            package.loaded['netman.tools.shell'] = nil
            package.loaded['netman.providers.podman'] = nil
            _fs_open = vim.loop.fs_open
            _fs_write = vim.loop.fs_write
            _fs_close = vim.loop.fs_close
        end)
        after_each(function()
            vim.loop.fs_open = _fs_open
            vim.loop.fs_write = _fs_write
            vim.loop.fs_close = _fs_close
        end)
        it("should bail out on received exit code", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 1, stdout = ""} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            vim.loop.fs_open = function(...) return '' end
            vim.loop.fs_write = function(...) return true end
            vim.loop.fs_close = function(...) return true end
            assert.is_false(require("netman.providers.podman").internal._write_file({}, {}), "Podman failed to fail properly on broken write request")
        end)
        it("should return true on successful write of file", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = ""} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            vim.loop.fs_open = function(...) return '' end
            vim.loop.fs_write = function(...) return true end
            vim.loop.fs_close = function(...) return true end
            assert.is_true(require("netman.providers.podman").internal._write_file({}, {}), "Podman failed to successfully write file")
        end)
    end)
    describe("#_create_directory", function()
        before_each(function()
            package.loaded['netman.tools.shell'] = nil
            package.loaded['netman.providers.podman'] = nil
        end)
        it("should bail out on received exit code", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 1, stdout = ""} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_false(require("netman.providers.podman").internal._create_directory("somecontainer", "somepath"), "Podman failed to fail properly on broken create directory request")
        end)
        it("should return true on successful write of file", function()
            local _shell = {CONSTANTS = SHELL_CONSTANTS}
            local _run = function(...) return {stderr = "", exit_code = 0, stdout = ""} end
            _shell.new = function(...) return {run = _run} end
            package.loaded['netman.tools.shell'] = _shell
            assert.is_true(require("netman.providers.podman").internal._create_directory("somecontainer", "somepath"), "Podman failed to successfully create directory")
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
