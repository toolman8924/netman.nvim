_G._QUIET = true -- This makes bootstrap shut up
vim.g.netman_log_level = 0

local spy = require("luassert.spy")
local describe = require('busted').describe
local it = require('busted').it
local before_each = require("busted").before_each
local after_each = require("busted").after_each
local pending = require("busted").pending

describe("Netman API #netman-api", function()
    before_each(function()
        package.loaded['netman.api'] = nil
    end)
    describe("#init_config", function()
        local _io = {}
        local _json = {}
        local api = nil
        before_each(function()
            _io.open = _G.io.open
            api = nil
            package.loaded['netman.tools.utils'] = nil
            _json.decode = _G.vim.fn.json_decode
        end)
        after_each(function()
            _G.io.open = _io.open
            api = nil
            _G.vim.fn.json_decode = _json.decode
        end)

        it("should not error if it cant open the configuration", function()
            api = require("netman.api")
            package.loaded['netman.tools.utils'].netman_config_path = ''
            _G.io.open = function() return false end
            assert.has_no.errors(function()
                api.internal.init_config()
            end)
        end)
        it("should not try to decode json if there is nothing to decode", function()
            api = require("netman.api")
            package.loaded['netman.tools.utils'].netman_config_path = ''
            _G.io.open = function()
                return {
                    lines = function() return function() return nil end end,
                    close = function() end
                }
            end
            local called = false
            _G.vim.fn.json_decode = function() called = true end
            api.internal.init_config()
            assert.is_false(called, "API attempted to decode invalid lines of configuration")
        end)
    end)
    describe("#init_augroups", function()
        local api = nil
        local _nvim_create_augroup = nil
        local _nvim_create_autocmd = nil
        before_each(function()
            api = require("netman.api")
            _nvim_create_augroup = vim.api.nvim_create_augroup
            _nvim_create_autocmd = vim.api.nvim_create_autocmd
        end)
        after_each(function()
            api = nil
            package.loaded['netman.api'] = nil
            vim.api.nvim_create_augroup = _nvim_create_augroup
            vim.api.nvim_create_autocmd = _nvim_create_autocmd
        end)
        it("should create the Netman auto group", function()
            local was_called = false
            vim.api.nvim_create_augroup = function(group, _)
                if group == 'Netman' then was_called = true end
            end
            api.internal.init_augroups()
            assert.is_true(was_called, "Netman Auto Group was not created")
        end)
    end)
    -- api.internal.validate_uri
    describe("#validate_uri", function()
        it("should return nil if the uri is not a shortcut and there is no provider for it", function()
            package.loaded['netman.providers'] = {}
            local api = require("netman.api")
            assert.is_nil(api.internal.validate_uri("jankuri://somepath"))
        end)
    end)
    -- api.load_provider
    describe("#load_provider", function()
        local required_attrs = {
                'name'
                ,'protocol_patterns'
                ,'version'
                ,'read'
                ,'write'
                ,'delete'
                ,'get_metadata'
        }
        before_each(function()
            package.loaded['netman.providers'] = {}
            package.loaded['dummy.provider'] = nil
            package.loaded['dummy.provider.1'] = nil
            package.loaded['dummy.provider.2'] = nil
            package.loaded['netman.api'] = nil
        end)
        -- We need to test the following things
        it("should not attempt to load a provider that is already loaded", function()
            local spied_importer = spy.new(function() end)
            local api = require("netman.api")
            api._providers.path_to_provider["jankprovider"] = { init = spied_importer }
            api.load_provider("jankprovider")
            assert.spy(spied_importer).was_not_called("Load provider attempted multiple loads of same provider")
        end)
        it("should notify the user when a provider doesn't exist", function()
            local called = false
            local api = require("netman.api")
            local logger = api.get_system_logger()
            local _errorn = logger.errorn
            logger.errorn = function(...) called = true end
            api.load_provider("non-existent-provider")
            logger.errorn = _errorn
            assert.is_true(called)
        end)
        it("should notify the user when a provider is invalid", function()
            package.loaded['dummy.provider.1'] = true
            package.loaded['dummy.provider.2'] = false
            local count = 0
            local api = require("netman.api")
            local logger = api.get_system_logger()
            local _errorn = logger.errorn
            logger.errorn = function(...) count = count + 1 end
            api.load_provider('dummy.provider.1')
            api.load_provider('dummy.provider.2')
            logger.errorn = _errorn
            assert.is_true(count >= 2)
        end)
        it("should fail to validate an invalid provider", function()
            local dummy_provider = {}
            package.loaded['dummy.provider'] = dummy_provider
            local api = require("netman.api")
            for index, _ in ipairs(required_attrs) do
                for _, attr in ipairs({table.unpack(required_attrs, 1, index)}) do
                    local val = nil
                    if attr == 'name' then val = "dummy_provider"
                    elseif attr == 'version' then val = '0.0'
                    elseif attr == 'protocol_patterns' then val = {'jankuri'}
                    else val = function() end end
                    dummy_provider[attr] = val
                end
                local missing_attrs = unpack(required_attrs, index + 1, #required_attrs)
                api.load_provider('dummy.provider')
                if type(missing_attrs) == 'string' then missing_attrs = {missing_attrs} end
                if missing_attrs then
                    for _, missing_attr in ipairs(missing_attrs) do
                        assert(api._providers.uninitialized["dummy.provider"].reason:find(missing_attr), string.format("Load Provider did not fail for missing attribute %s", missing_attr))
                    end
                end
            end
        end)
        it("should call init if its provided", function()
            local dummy_provider = {}
            for index, _ in ipairs(required_attrs) do
                for _, attr in ipairs({table.unpack(required_attrs, 1, index)}) do
                    local val = nil
                    if attr == 'name' then val = "dummy_provider"
                    elseif attr == 'version' then val = '0.0'
                    elseif attr == 'protocol_patterns' then val = {'jankuri'}
                    else val = function() end end
                    dummy_provider[attr] = val
                end
            end
            package.loaded['dummy.provider'] = dummy_provider
            local api = require("netman.api")

            -- luassert's spy functionality is quite lacking.
            -- Instead of making my own altogether, I am just going
            -- to piece together what I need as I need them
            local _unload_provider = api.unload_provider
            local call_count = 0
            local spied_unload_provider = function(...)
                call_count = call_count + 1
                _unload_provider(...)
                package.loaded['dummy.provider'] = dummy_provider
            end
            api.unload_provider = spied_unload_provider
            dummy_provider.init = function()
                error("DED!")
            end
            api.load_provider('dummy.provider')
            assert.is_equal(1, call_count, "Load Provider did not unload failed provider init!")

            call_count = 0
            dummy_provider.init = function() return false end
            api.load_provider('dummy.provider')
            assert.is_equal(1, call_count, "Load provider did not unload provider with unsafe init")

            call_count = 0
            dummy_provider.init = function() end
            api.load_provider('dummy.provider')
            assert.is_equal(1, call_count, "Load Provider did not unload provider with no init return")

            call_count = 0
            dummy_provider.init = function() return true end
            assert.is_equal(0, call_count, "Load Provider unloaded properly inited provider")
            api.unload_provider = _unload_provider
        end)
        it("should override existing provider of same protocol pattern", function()
            local dummy_provider1 = {}
            local dummy_provider2 = {}
            for index, _ in ipairs(required_attrs) do
                for _, attr in ipairs({table.unpack(required_attrs, 1, index)}) do
                    local val = nil
                    if attr == 'name' then val = "dummy_provider"
                    elseif attr == 'version' then val = '0.0'
                    elseif attr == 'protocol_patterns' then val = {'jankuri'}
                    else val = function() end end
                    dummy_provider1[attr] = val
                    dummy_provider2[attr] = val
                end
            end
            package.loaded['dummy.provider.1'] = dummy_provider1
            package.loaded['dummy.provider.2'] = dummy_provider2
            local api = require("netman.api")
            api.load_provider('dummy.provider.1')

            local call_count = 0
            local overriden_name = nil
            local _unload_provider = api.unload_provider
            api.unload_provider = function(...)
                call_count = call_count + 1
                overriden_name = select(1, ...)
                _unload_provider(...)
            end
            api.load_provider('dummy.provider.2')
            assert.is_equal(1, call_count, "Load Provider did not unload overriden provider!")
            assert.is_equal('dummy.provider.1', overriden_name, "Load Provider did not unload the correct provider on override")
        end)
        it("should prevent core providers for overriding third party providers", function()
            local dummy_provider1 = {}
            local dummy_provider2 = {}
            for index, _ in ipairs(required_attrs) do
                for _, attr in ipairs({table.unpack(required_attrs, 1, index)}) do
                    local val = nil
                    if attr == 'name' then val = "dummy_provider"
                    elseif attr == 'version' then val = '0.0'
                    elseif attr == 'protocol_patterns' then val = {'jankuri'}
                    else val = function() end end
                    dummy_provider1[attr] = val
                    dummy_provider2[attr] = val
                end
            end
            package.loaded['dummy.provider.1'] = dummy_provider1
            package.loaded['netman.providers.dummy_provider'] = dummy_provider2
            local api = require("netman.api")
            api.load_provider('dummy.provider.1')
            api.load_provider('netman.providers.dummy_provider')
            assert.is_not_nil(api._providers.uninitialized['netman.providers.dummy_provider'], "Load Provider allowed core provider to override third party provider")
        end)
    end)
    -- api.unload_provider
    describe("#unload_provider", function()
        before_each(function()
            package.loaded['netman.providers'] = {}
            package.loaded['dummy.provider.1'] = nil
            package.loaded['dummy.provider.2'] = nil
            package.loaded['netman.api'] = nil
        end)
        it("should silently fail when unloading an invalid provider", function()
            assert.has_no.errors(
                function() require("netman.api").unload_provider("dummy.provider") end,
                "Unload Provider failed to safely unload invalid provider"
            )
        end)
        it("should unload all hooks for a provider", function()
            local dummy_provider1 = {}
            dummy_provider1.protocol_patterns = { "junkuri" }
            package.loaded['dummy.provider.1']= dummy_provider1
            local api = require("netman.api")
            api._providers.protocol_to_path['junkuri'] = 'dummy.provider.1'
            api._providers.path_to_provider['dummy.provider.1'] = dummy_provider1
            api.unload_provider('dummy.provider.1')
            assert.is_nil(api._providers.protocol_to_path['junkuri'], "Unload Provider failed to remove protocol to path map")
            assert.is_nil(api._providers.path_to_provider['dummy.provider.1'], "Unload Provider failed to remove provider path map")
        end)
        it("should burn all traces of the provider for memory", function()
            local dummy_provider1 = {}
            dummy_provider1.protocol_patterns = { "junkuri" }
            package.loaded['dummy.provider.1']= dummy_provider1
            local api = require("netman.api")
            api._providers.protocol_to_path['junkuri'] = 'dummy.provider.1'
            api._providers.path_to_provider['dummy.provider.1'] = dummy_provider1
            api.unload_provider('dummy.provider.1')
            assert.is_nil(api._providers.protocol_to_path['junkuri'], "Unload Provider failed to remove protocol to path map")
            assert.is_nil(api._providers.path_to_provider['dummy.provider.1'], "Unload Provider failed to remove provider path map")
            assert.is_nil(package.loaded['dummy.provider.1'], "Unload Provider failed to remove provider from lua memory")
        end)
        it("should justify the removal of the provider for later viewing", function()
            local dummy_provider1 = {}
            dummy_provider1.protocol_patterns = { "junkuri" }
            package.loaded['dummy.provider.1']= dummy_provider1
            local api = require("netman.api")
            api._providers.protocol_to_path['junkuri'] = 'dummy.provider.1'
            api._providers.path_to_provider['dummy.provider.1'] = dummy_provider1
            api.unload_provider('dummy.provider.1')
            assert.is_not_nil(api._providers.uninitialized['dummy.provider.1'], "Unload Provider did _not_ justify the removal of the provider")
        end)
    end)
    describe("#unload_buffer", function()
        before_each(function()
        -- "Load" a provider and uri into memory to verify that things work as expected
        end)
        pending("should call \"close_connection\" on an associated provider after buffer is closed", function()
        end)
    end)
    -- api.read
    describe('#read', function()
        local api = nil
        local api_options = require("netman.tools.options").api
        local provider = nil
        before_each(function()
            api = require("netman.api")
            provider = nil
            api.internal.validate_uri = function(uri) return uri, provider end
        end)
        after_each(function()
            package.loaded['netman.api'] = nil
        end)
        pending("read contract changed - update to current api.read/provider response behavior")
        pending("read contract changed - invalid read type")
        pending("read contract changed - no data returned")
        pending("read contract changed - stream type")
        pending("read contract changed - file type")
        pending("read contract changed - explore type")
    end)
    -- api.write
    describe('#write', function()
        -- Figure out a way to verify that an action is happening asychronously?
        -- A reasonable way to do this would be to have our provider's 
        -- "write" function do a sleep for some (very short) amount of time.
        -- Anything longer than nothing would mean that it should still be running
        -- when api.write finishes and thus we can verify that it is asynchronous.
        -- If the "long running" write function is complete by the time api.write
        -- finishes, that means it was _not_ async. Das bad
        local api = nil
        local provider = nil
        local _nvim_buf_get_lines = nil
        before_each(function()
            api = require("netman.api")
            provider = nil
            api.internal.validate_uri = function(uri) return uri, provider end
            _nvim_buf_get_lines = vim.api.nvim_buf_get_lines
            -- Adding the empty params because sumneko complains like a ass
            -- when other things are using the _real_ vim.api.nvim_buf_get_lines
            vim.api.nvim_buf_get_lines = function(_, _, _, _) return {"line1"} end
        end)
        after_each(function()
            vim.api.nvim_buf_get_lines = _nvim_buf_get_lines
            package.loaded['netman.api'] = nil
        end)
        pending("should call write asynchronously", function()

        end)
        it("should call the provider's write function", function()
            local ran = false
            provider = {
                write = function()
                    ran = true
                end
            }
            api.write(0, '')
            assert.is_true(ran, "Write did not call provider's write function")
        end)
        it("should return failure when there is no provider for the uri", function()
            local result = api.write(0, '')
            assert.is_not_nil(result)
            assert.is_false(result.success)
        end)
    end)
    -- api.delete
    describe('#delete', function()
        -- Figure out a way to verify that an action is happening asychronously?
        -- A reasonable way to do this would be to have our provider's 
        -- "delete" function do a sleep for some (very short) amount of time.
        -- Anything longer than nothing would mean that it should still be running
        -- when api.delete finishes and thus we can verify that it is asynchronous.
        -- If the "long running" delete function is complete by the time api.delete
        -- finishes, that means it was _not_ async. Das bad
        local api = nil
        local provider = nil
        before_each(function()
            api = require("netman.api")
            provider = nil
            api.internal.validate_uri = function(uri) return uri, provider end
        end)
        after_each(function()
            package.loaded['netman.api'] = nil
        end)
        pending("should call delete asychronously", function()
        
        end)
        it("should call the provider's delete function", function()
            local ran = false
            provider = {
                delete = function()
                    ran = true
                end
            }
            api.delete(0, '')
            assert.is_true(ran, "Delete did not call provider's delete function")
        end)
        it("should return failure when there is no provider for the uri", function()
            local result = api.delete('')
            assert.is_not_nil(result)
            assert.is_false(result.success)
        end)
    end)
    -- api.init
    describe('#init', function()
        after_each(function()
            package.loaded['netman.api'] = nil
        end)
        it("should init the auto groups", function()
            local was_called = false
            local _create_augroup = vim.api.nvim_create_augroup
            vim.api.nvim_create_augroup = function(group, _)
                if group == 'Netman' then was_called = true end
                return 1
            end
            local api = require("netman.api")
            api._inited = nil
            api.init()
            vim.api.nvim_create_augroup = _create_augroup
            assert.is_true(was_called, "API init did not reach out to create au groups")
        end)
        it("should should load system providers", function()
            local system_providers = require("netman.providers")
            local api = require("netman.api")
            for _, provider in ipairs(system_providers) do
                assert.is_not_nil(api._providers.path_to_provider[provider], string.format("API did not load system provider %s", provider))
            end
        end)
    end)
    -- api.get_metadata
    describe("#get_metadata", function()
        local api = nil
        local was_called = nil
        before_each(function()
            api = require("netman.api")
            was_called = false
            local provider = {
                get_metadata = function(_, _, keys)
                    was_called = true
                    local metadata = {}
                    for _, key in ipairs(keys) do
                        metadata[key] = 1
                    end
                    return { success = true, data = metadata }
                end
            }
            api.internal.validate_uri = function(_)
                return _, provider
            end
        end)
        after_each(function()
            was_called = false
            package.loaded['netman.api'] = nil
        end)
        it("should have a default set of metadata keys to return if you don't provide any", function()
            local metadata = api.get_metadata('')
            assert.is_not_nil(metadata, "API did not return a default keyset for metadata")
        end)
        it("should return the metadata for the provided keys", function()
            local metadata_keys = {'ATIME_SEC'}
            local metadata = api.get_metadata('', metadata_keys)
            assert.is_not_nil(metadata[metadata_keys[1]], string.format("API did not return the requested valid metadata for %s", metadata_keys[1]))
        end)
        it("should reach out to the provider to get metadata", function()
            api.get_metadata('')
            assert.is_true(was_called, "API did not reach out to the provider")
        end)
        it("should sanitize the provider's returned metadata keys to ensure consistency", function()
            local metadata_keys = {'ATIME_SEC', 'INVALID_KEY'}
            local metadata = api.get_metadata('', metadata_keys)
            assert.is_not_nil(metadata[metadata_keys[1]], string.format("API did not return metadata for valid metadata key %s", metadata_keys[1]))
            assert.is_nil(metadata[metadata_keys[2]], string.format("API returned metadata for invalid metadata key %s", metadata_keys[2]))
        end)
    end)
end)
