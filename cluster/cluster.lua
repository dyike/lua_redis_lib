local setmetatable = setmetatable
local redis = require 'resty.redis'
local rawget = rawget
local crc16 = require 'crc16'
local cjson = require 'cjson.safe'

-- global var
node_cache = {}

local _M = {
    VERSION = '0.00',
    conf = {},
}


function _M.connect(self, host, port)
    local red = redis:new()
    local res, err = red:connect(host, port)
    if not res then
        return nil, err
    end

    if self.conf.auth then
        local res, err = red:auth(self.conf.auth)
        if not res then
            return nil, err
        end
    end
    return red
end


function _M:close(red)
    if not red or type(red) ~= 'table' then
        return nil, "error redis handle type: " .. type(red)
    end
    local res, err = red:set_keepalive(
        self.conf.keep_time,
        self.conf.keep_size
    )
    if not res then
        return nil, err
    end
end

function _M.new(self, conf)
    self.conf.name = conf.name or 'default'
    self.conf.auth = conf.auth or nil
    self.conf.timeout = conf.timeout or 3000
    self.conf.keep_time = conf.keep_time or 10000
    self.conf.keep_size = conf.keep_size or 100
    self.conf.server = conf.server[math.random(1, #conf["server"])] or nil

    local ostime, nodes, name = ngx.time(), {}, self.conf.name
    if node_cache[name] and node_cache[name][ostime] then
        nodes = node_cache[name][tostring(ostime)]
    else
        local red, err = self:connect(self.conf.server.host, self.conf.server.port)
        if not err then
            local res, err = red:cluster('slots')
            for i, node in pairs(res) do
                nodes[i] = {
                    min_hash_slot = node[1],
                    max_hash_slot = node[2],
                    host = node[3][1],
                    port = node[3][2],
                }
            end
        end
        self:close(red)
        node_cache[name] = {}
        node_cache[name][tostring(ostime)] = nodes
    end
    redis:set_timeout(self.conf.timeout)

    return setmetatable({
        nodes = nodes,
    }, {__index = _M})
end

function _M.get_node(self, key)
    local hash_slot = crc16.compute(key) % 16384   -- Redis 集群的键空间被分割为 16384 个槽（slot）， 集群的最大节点数量也是 16384 个。

    for _, node in pairs(self.nodes) do
        if hash_slot >= node['min_hash_slot'] and hash_slot <= node['max_hash_slot'] then
            return node
        end
    end
end

function _M._do_cmd(self, cmd, key, ...)
    local node = self.get_node(self, key)

    if not node then
        return nil, 'node not exits'
    end

    local reqs = rawget(self, '_reqs')
    if reqs then
        local hash = node.host .. ':' .. node.port
        local req = reqs[hash]
        if not req then
            req = {
                node = {
                    host = node.host,
                    port = node.port,
                },
                cmds = {},
            }
        end

        nreq_cmd = #req.cmds + 1
        req.cmds[nreq_cmd] = {
            cmd = cmd,
            key = key,
            arg = {...},
            counter = self._reqs_counter
        }
        self._reqs[hash] = req
        self._reqs_counter = self._reqs_counter + 1
    else
        local red, err = self:connect(node.host, node.port)
        if not red then
            return nil, err
        end
        local res, err = red[cmd](red, key, ...)

        self:close(red)
        return res, err
    end
end


function _M.init_pipeline(self)
    self._reqs = {}
    self._reqs_counter = 1
end


function _M.cancel_pipeline(self)
    self._reqs = {}
    self._reqs_counter = 0
end

function _M.commit_pipeline(self)
    local reqs = rawget(self, "_reqs")
    if not reqs or  type(reqs) ~= 'table' or reqs == {} then
        return nil, "requst not exists"
    end

    local res, red, err = {}, nil, nil
    for i, req in pairs(req.cmds) do
        if #req.cmds > 0 then
            red, err = self:connect(req.node.host, req.node.port)
            if err then
                return red, err
            end
            red:init_pipeline()
            for i, cmd in pairs(req.cmds) do
                if #cmd.arg > 0 then
                    red[cmd.cmd](red, cmd.key, unpack(cmd.arg))
                else
                    red[cmd.cmd](red, cmd.key)
                end
            end

            local res_date, err = red:commit_pipeline()
            for i, cmd in pairs(req.cmds) do
                res[cmd.counter] = res_data[i]
            end

            self:close(red)
        end
    end

    return res
end

setmetatable(_M, {
    __index = function(self, cmd)
        local method = function(self, ...)
            return self._do_cmd(self, cmd, ...)
        end
        return method
    end
})


return _M
