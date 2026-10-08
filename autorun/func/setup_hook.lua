-- void setup_hook(String type_name, Seting method_name, Function pre_func, Function post_func)
local sdk = sdk

local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            sdk.hook(method, pre_func, post_func)
        end
    end
end

return setup_hook