-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %                                      .  .                       %
-- %                                   .  .  .  .                    %
-- %                                   .  |  |  .                    %
-- %                                .  |        |  .                 %
-- %                                .              .                 %
-- %  ___     ___    _________    . |  (\.|\/|./)  | .   ___   ____  %
-- % |   |   |   |  /    _    \   .   (\ |||||| /)   .  |   | /   /  %
-- % |   |___|   | |    /_\    |  |  (\  |/  \|  /)  |  |   |/   /   %
-- % |           | |           |    (\            /)    |       /    %
-- % |    ___    | |    ___    |   (\              /)   |       \    %
-- % |   |   |   | |   |   |   |    \      \/      /    |   |\   \   %
-- % |___|   |___| |___|   |___|     \____/\/\____/     |___| \___\  %
-- %                                     |0\/0|                      %
-- %                                      \/\/                       %
-- %                                       \/                        %
-- %                                                                 %
-- %                                                                 %
-- % A simple http and websocket(XMPP) reverse proxy                 %
-- %                                                                 %
-- % Author: ZhangFeng aka Justin Zhang <schnell18@gmail.com>        %
-- % Date: 2018-02                                                   %
-- %                                                                 %
-- % Copyright 2018 and beyond                                       %
-- %                                                                 %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
local _M = {}
_M._VERSION = '1.0.0'

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %            Private function definition goes below            %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
local function getn(table)
    local n = 0
    for i, _ in ipairs(table) do
        n = n + 1
    end
    return n
end

local function domain_replace_factory(from, to)
    function rewrite_func(data)
        data, _ = string.gsub(data, from, to)
        return data
    end
    return rewrite_func
end

local function default_downstream_filter_factory(from, to)
    function subst(prefix)
        return prefix .. to
    end
    function rewrite_func(data)
        data, _ = string.gsub(data, "(https?://.-%.)" .. from, subst)
        return data
    end
    return rewrite_func
end

function load_balance_randomly(upstream)
    local up = require "ngx.upstream"
    local hosts = {}
    for _, u in ipairs(up.get_servers(upstream)) do
        for k, v in pairs(u) do
            if k == "addr" then
                if type(v) == "table" then
                    for _, h in ipairs(v) do
                        hosts[#hosts + 1] = h
                    end
                else
                    hosts[#hosts + 1] = v
                end
            end
        end
    end
    return hosts[math.random(1, getn(hosts))]
end

local function upstream_lookup_factory(upstream, context_path)
    function rewrite_func(data)
        local gateway = load_balance_randomly(upstream)
        return gateway .. (context_path or "")
    end
    return rewrite_func
end

local function lookup_im_upstream(upstream, protocol)
    local gateway = load_balance_randomly(upstream)
    return protocol .. "://" .. gateway
end

local function match_content_type(actual, expectedTypes)
    if not actual then return false end
    for _, exepected in ipairs(expectedTypes) do
        local a, _ = string.find(actual, exepected)
        if a == 1 then return true end
    end
    return false
end

local function rewrite_cookie_domain(simple_rewrite_func)
    local oldCookies = ngx.header["Set-Cookie"]
    if not oldCookies then return end
    if type(oldCookies) == "string" then
        oldCookies = {oldCookies}
    end
    local newCookies = {}
    for i, cookie in ipairs(oldCookies) do
        newCookies[i] = simple_rewrite_func(cookie)
    end
    ngx.header["Set-Cookie"] = newCookies
end
 
local function rewrite_redirect(simple_rewrite_func)
    local oldLocation = ngx.header["Location"]
    if oldLocation then
        local newLoc = simple_rewrite_func(oldLocation)
        ngx.header["Location"] = newLoc
    end
end
 
local function set_cors_headers(default_origin)
    local origin = ngx.var.http_origin
    if not origin then
        local referrer = ngx.var.http_referrer
        if referrer then
            local from, to, err = ngx.re.find(referrer, "https?://(.*)/", "jos")
            if not err then
                origin = "https://" .. string.sub(referrer, from, to)
            end
        end
    end
    if not origin then
        origin = default_origin
    end
    ngx.header["Access-Control-Allow-Origin"]  = origin
    ngx.header["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    ngx.header["Access-Control-Allow-Headers"] = "DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Jk-Host,originalUrl"
    ngx.header["Access-Control-Allow-Credentials"] = "true";
    ngx.header["Content-Type"] = "application/json;charset=UTF-8"
end
 
local function relay(dir, wb_down, wb_up, typ, data, filters)
    if not data then
        return true, 200
    end

    local bytes, err
    if typ == "text" then
        ngx.log(ngx.INFO, "prior relay to " .. dir .. " w/: ", data)
        if type(filters) == "table" then
            for _, filter in ipairs(filters) do
                if type(filter) == "function" then
                    data = filter(data)
                end
            end
        end
        if dir == "downstream" then
            bytes, err = wb_down:send_text(data)
            ngx.log(ngx.INFO, "relayed to " .. dir .. " w/: ", data)
        else
            bytes, err = wb_up:send_text(data)
        end
    elseif typ == "binary" then
        if dir == "downstream" then
            bytes, err = wb_down:send_binary(data)
        else
            bytes, err = wb_up:send_binary(data)
        end
    elseif typ == "ping" then
        if dir == "downstream" then
            bytes, err = wb_down:send_ping() -- ping downstream
            bytes, err = wb_up:send_pong() -- pong upstream
        else
            bytes, err = wb_up:send_ping() -- ping upstream
            bytes, err = wb_down:send_pong() -- pong downstream
        end
    elseif typ == "pong" then
        ngx.log(ngx.INFO, dir .. " ponged")
    elseif typ == "close" then
        ngx.log(ngx.INFO, dir .. " closed")
        return false, 200
    else
        ngx.log(ngx.INFO, "Ignored frame of type: " .. (typ or "n/a") .. " data: "  .. (data or "nil") .. " for " .. dir)
        return true, 200
    end

    if not bytes then
      ngx.log(ngx.ERR, "failed to send frame: ", err)
      return false, 444
    end

    return true, 200
end


-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %              Public class definition goes below              %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function _M:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function _M:http_reverse_proxy()
    ngx.log(ngx.INFO, "Enter http_reverse_proxy()")
    -- return immediately for OPTIONS request
    local method = ngx.req.get_method()
    if method == "OPTIONS" then
        ngx.status = ngx.HTTP_OK
        set_cors_headers(default_cors_origin)
        ngx.send_headers()
        return
    end
 
    local body_filters, err = self:get_body_filters()
    if not body_filters then
        ngx.log(ngx.ERR, "Bad body filters config: " .. err)
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        ngx.say("Error: ", err)
        return
    end
    
    local dest_host_func = domain_replace_factory(self.outer_domain, self.inner_domain)
    local backend_func
    if self.upstream then
        backend_func = upstream_lookup_factory(self.upstream, self.context_path)
    else
        backend_func = dest_host_func
    end

    local simple_filter       = domain_replace_factory(self.inner_domain, self.outer_domain)
    local with_cors_header    = self.with_cors_header or false
    local default_cors_origin = self.default_cors_origin
    local content_type        = self.content_type

    -- rewrite request to point to inner domain
    local dest_host = backend_func(ngx.var.http_host)
    -- prepare request data: copy cookie, etc
    local dest_uri = "http://" .. dest_host .. ngx.var.request_uri
    local http = require "resty.http"
    local httpc = http.new()
    local params = {
        method = method,
        headers = {
            ["Content-Type"]      = ngx.var.content_type,
            ["Host"]              = dest_host_func(ngx.var.http_host),
            ["X-Real-IP"]         = ngx.var.remote_addr,
            ["X-Forwarded-For"]   = ngx.var.http_x_forwarded_for,
            ["X-Forwarded-Proto"] = ngx.var.http_x_forwarded_proto,
            ["Cookie"]            = ngx.var.http_cookie,
            ["User-Agent"]        = ngx.var.http_user_agent,
            ["Accept-Encoding"]   = nil,
        }
    }
    -- clear Accept-Encoding so that we get response uncompressed
    -- pass body if requested method is POST
    if method == "POST" or method == "PUT" then
        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        if data then
            params["body"] = data
        else
            local file = ngx.req.get_body_file()
            if file then
                params["body"] = file:read("*a")
            end
        end
    end
    -- make http request
    local res, err = httpc:request_uri(dest_uri, params)
    if not res then
        ngx.log(ngx.WARN, "=== " .. dest_uri .. " failed w/ " .. err)
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        ngx.say("failed to request: ", err)
        return
    end
    -- filter and copy headers:
    --  1. remove Transfer-Encoding
    --  2. remove Connection
    --  3. remove Vary
    for k,v in pairs(res.headers) do
        if (k ~= "Transfer-Encoding" and k ~= "transfer-encoding") and
           (k ~= "Connection" and k ~= "connection") and
           (k ~= "Vary" and k ~= "vary") then
            ngx.header[k] = v
        end
    end
    --  2. rewrite cookie domain
    rewrite_cookie_domain(simple_filter)
    --  3. rewrite redirect response header
    rewrite_redirect(simple_filter)
    -- rewrite body
    local body = res.body
    if res.status == ngx.HTTP_OK then
        local exps = {
           "application/javascript",
           "application/json",
           "text/plain",
           "text/html",
           "text/css",
        }
        local actual = res.headers["Content-Type"] or res.headers["content-type"]
        if match_content_type(actual, exps) then
            ngx.log(ngx.INFO, "Original body: " .. body)
            for _, filter in ipairs(body_filters) do
                body = filter(body, self.inner_domain, self.outer_domain)
            end
            ngx.log(ngx.INFO, "Rewritten body: " .. body)
        end
    end
    -- send response to client
    if with_cors_header then
        set_cors_headers(default_cors_origin)
    end
    if content_type then
        ngx.header["Content-Type"] = content_type
    end
    ngx.status = res.status
    ngx.header["Content-Length"] = string.len(body)
    ngx.say(body)
end

function _M:im_reverse_proxy()
    ngx.log(ngx.INFO, "Enter im_reverse_proxy()")
    local downstream_filters, err = self:get_downstream_filters()
    if not downstream_filters then
        ngx.log(ngx.ERR, "Bad downstream filters config: " .. err)
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        ngx.say("Error: ", err)
        return
    end

    local client = require "resty.websocket.client"
    local server = require "resty.websocket.server"
    local wbs, err = server:new {
        timeout = 500,  -- in milliseconds
        max_payload_len = 65535,
    }

    if not wbs then
      ngx.log(ngx.ERR, "failed to new websocket: ", err)
      return ngx.exit(444)
    end

    local wbc, err = client:new {
        timeout = 500,
        max_payload_len = 65535,
    }
    local opts = {
        ["protocols"] = "xmpp",
        ["cookies"] = ngx.var.http_cookie,
    }
    local backend = lookup_im_upstream(self.upstream, self.protocol or "wss")
    local ok, err = wbc:connect(backend, opts)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: " .. err)
        wbs:send_close()
        return ngx.exit(444)
    end

    local exit_code = 200
    local continue = true
    while true do
        local data1, typ1, err = wbs:recv_frame()
        if wbs.fatal then
            ngx.log(ngx.ERR, "failed to receive frame from downstream: ", err)
            exit_code = 444
            break
        end

        -- relay data from downstream to upstream
        continue, exit_code = relay("upstream", wbs, wbc, typ1, data1)
        if not continue then break end

        local data2, typ2, err = wbc:recv_frame()
        if wbc.fatal then
            ngx.log(ngx.ERR, "failed to receive frame from upstream: ", err)
            exit_code = 444
            break
        end

        continue, exit_code = relay("downstream", wbs, wbc, typ2, data2, downstream_filters)
        if not continue then break end

    end

    wbc:send_close()
    wbs:send_close()
    return ngx.exit(exit_code)
end

function _M:get_downstream_filters()
    local filters = self.downstream_filters
    if not filters then
        return {
            default_downstream_filter_factory(
                self.inner_domain,
                self.outer_domain
            )
        }
    end
    local good_filters = 0
    for _, f in ipairs(filters) do
        if not type(f) == 'function' then
            return nil, "bad downstream filter type: " .. type(f)
        else
            good_filters = good_filters + 1 
        end
    end
    if good_filters == 0 then
        return {
            default_downstream_filter_factory(
                self.inner_domain,
                self.outer_domain
            )
        }
    else
        return filters
    end
end

function _M:get_body_filters()
    local filters = self.body_filters
    if not filters then
        return {_M.default_body_filter}
    end
    local good_filters = 0
    for _, f in ipairs(filters) do
        if not type(f) == 'function' then
            return nil, "bad body filter type: " .. type(f)
        else
            good_filters = good_filters + 1 
        end
    end

    if good_filters == 0 then
        return {_M.default_body_filter}
    else
        return filters
    end
end


-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %             Public function definition goes below            %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function _M.default_body_filter(data, from, to)
    data, _ = string.gsub(data, from, to)
    return data
end

return _M
-- vim: set ai nu expandtab ts=4 sw=4 tw=72 syntax=lua: