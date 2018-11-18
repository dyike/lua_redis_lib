# Lua Redis Client 


## Sentinel Client

### conf setting 

```lua
redis_conf = {
    connections = {
        {host = '127.0.0.1', port = '6379'},
        {host = '127.0.0.1', port = '6389'},
    },
    options = {
        replication = 'sentinel',
        service = 'service_name',
        parameters = {
            password = 'password',
            database = 1,
        }
    },
}

```

### use `s_redis.lua`

So easy! Lookup Code!

## Cluster Client 

### conf setting 

```lua
redis_conf = {
    server = {
        {host = "127.0.0.1", port = 6379},
        {host = "127.0.0.1", port = 6389},
    }
}
```

### use `c_redis.lua`

```lua
local redis = require 'c_redis.lua'

local redis_conf = redis_conf

local rc = redis.new(redis_conf)

local res, err = rc:get(redis_key)

--- ...
```
