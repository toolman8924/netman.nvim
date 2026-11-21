_G._QUIET = true
vim.g.netman_log_level = 0

local describe = require('busted').describe
local it = require('busted').it
local provider_names = require("netman.providers.init")

local provider
for _, provider_name in ipairs(provider_names) do
    _status, provider = pcall(require, provider_name)
    describe("misc", function()
        it("should have a read attribute", function()
            assert.is_not_nil(provider.read, string.format("%s does not contain a read function", test_provider))
            assert.is_equal(type(provider.read), "function", string.format("%s's read attribute is not a function", test_provider))
        end)
        it("should have a write attribute", function()
            assert.is_not_nil(provider.write, string.format("%s does not contain a write function", test_provider))
            assert.is_equal(type(provider.write), "function", string.format("%s's write attribute is not a function", test_provider))
        end)
        it("should have a delete attribute", function()
            assert.is_not_nil(provider.delete, string.format("%s does not contain a delete function", test_provider))
            assert.is_equal(type(provider.delete), "function", string.format("%s's delete attribute is not a function", test_provider))
        end)
        it("should have a get_metadata attribute", function()
            assert.is_not_nil(provider.get_metadata, string.format("%s does not contain a get metadata function", test_provider))
            assert.is_equal(type(provider.get_metadata), "function", string.format("%s's get_metadata attribute is not a function", test_provider))
        end)
        it("should have a name attribute", function()
            assert.is_not_nil(provider.name, string.format("%s is missing a name attribute", test_provider))
            assert.is_equal(type(provider.name), "string", string.format("%s's name attribute is not a string", test_provider))
        end)
        it("should have a protocol_patterns attribute", function()
            assert.is_not_nil(provider.protocol_patterns, string.format("%s is missing a protocol_patterns attribute", test_provider))
            assert.is_equal(type(provider.protocol_patterns), "table", string.format("%s's protocol_patterns is not a table", test_provider))
            assert.is_true(#provider.protocol_patterns > 0, string.format("%s's protocol_patterns cannot be empty", test_provider))
        end)
        it("should have a version attribute", function()
            assert.is_not_nil(provider.version, string.format("%s is missing a version attribute", test_provider))
            assert.is_true(type(provider.version) == 'number' or type(provider.version) == 'string', string.format("%s's version attribute must be either a string or number", test_provider))
        end)
    end)

    describe("read", function()

    end)
    describe("write", function()

    end)
    describe("get_metadata", function()

    end)
    describe("delete", function()

    end)
    describe("init", function()

    end)
    describe("close_connection", function()

    end)
end
