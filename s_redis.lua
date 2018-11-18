local _M = {
    version = 20181118
}

local cjson = require 'cjson.safe'
local redis = require 'resty.redis.connector'
local serpent = require 'serpent'


local function connect(redis_conf)
    local rc = redis.new({
        connect_timeout = 100,
    })
    redis_conf = redis_conf
    local url = ''
    local db = redis_conf.options.parameters.database
    local password = ''
    if redis_conf.options.parameters.password then
        password = redis_conf.options.parameters.password..'@'
    end

    local connect_conf = {}
    if redis_conf.options.replication == 'sentinel' then
        local service = redis_conf.options.service
        connect_conf = {
            url = 'sentinel://'..password..service..':a/'..db,
            sentinels = redis_conf.connections,
        }
    else
        local host = redis_conf.connections[1].host
        local port = redis_conf.connections[1].port
        connect_conf = {
            url ='redis://'..password..host..':'..port..'/'..db,
        }
    end
    ngx.log(ngx.ERR, 'CONNECT_REDIS_CONF '..serpent.block(connect_conf))
    local ok, err = rc:connect(connect_conf)
    assert(ok, 'REDIS_FAILED_TO_CONNECT_'..(err or '')..serpent.block(redis_conf))
    return ok
end


function _M.new(conf)
    local instance = setmetatable({}, {
        __index = function(_, method)
            return setmetatable({}, {
                __call = function(_, ...)
                    local retry = 1
                    local conn, ret, err
                    while retry > 0 do
                        conn = connect(conf)
                        if conn then
                            ret, err  = conn[method](conn, ...)
                            if type(ret) == 'userdata' then
                                return nil
                            end
                            if ret then
                                conn:set_keepalive(10000, 10)
                                return ret
                            end
                            conn:close()
                        end
                        ngx.log(ngx.ERR, 'REDIS_RETRY_', retry, '_ERROR_', err)
                        retry = retry - 1
                        ngx.sleep(0.05)
                    end
                    return nil, err
                end
            })
        end
    })
    return instance
end

return _M
