local _M = {
    version = 20181118
}

local cjson = require 'cjson.safe'
local redis_cluster = require 'resty.rcluster'

function _M.new(conf)
    local red = redis_cluster:new(conf)
    return red
end

return _M

