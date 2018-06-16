-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %                                                              %
-- % PAJK specific rewrite rules                                  %
-- %                                                              %
-- % Author: ZhangFeng aka Justin Zhang <schnell18@gmail.com>     %
-- % Date: 2018-02                                                %
-- %                                                              %
-- % Copyright 2018 and beyond                                    %
-- %                                                              %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
local _M = {}
_M._VERSION = '1.0.0'

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %            Private function definition goes below            %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function rewrite_base64(body, rewrite_func)
    local cjson = require "cjson"
    local tbl = cjson.decode(body)
    if tbl.content and tbl.content[1] and #tbl.content[1].booths > 0 then
        for _, v in pairs(tbl.content[1].booths) do
            for k1, v1 in pairs(v) do
                if k1 == 'paramBinding' then
                    v[k1] = ngx.encode_base64(rewrite_func(ngx.decode_base64(v1)))
                 end
             end
        end
        return cjson.encode(tbl)
    end
    return body
end

local function getn(table)
    local n = 0
    for i, _ in ipairs(table) do
        n = n + 1
    end
    return n
end

local function rewrite_domain_func(body, from, to)
    body, _ = string.gsub(body, from, to)
    return body
end

local function downgrade_protocol_func(body)
    body, _ = string.gsub(body, "https://", "http://")
    return body
end

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-- %             Public function definition goes below            %
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-- im special handling, wss port replacement and JIDHOST must not be changed
function _M.im_rewrite_filter(body, inner_domain, outer_domain)
    if ngx.re.match(ngx.var.request_uri, "cable(-shadow)?/scripts/app.*.js", "ojs") then
        -- restore JID host domain
        local from_str = 'XMPP.JIDHOST="im.test.' .. outer_domain .. '"'
        local to_str = 'XMPP.JIDHOST="im.test.' .. inner_domain .. '"'
        body, c = string.gsub(body, from_str, to_str)
        -- replace wss port 5291 to 443
        local from_str = 'XMPP.SERVICE_PORT=5291'
        local to_str = 'XMPP.SERVICE_PORT=443'
        body, c = string.gsub(body, from_str, to_str)
    elseif ngx.re.match(ngx.var.request_uri, "im-cs-m/js/im-cs-m.*.js", "ojs") then
        -- restore JID host domain
        local from_str = 'jid:"im.test.' .. outer_domain .. '"'
        local to_str = 'jid:"im.test.' .. inner_domain .. '"'
        body, c = string.gsub(body, from_str, to_str)
        -- replace wss port 5291 to 443
        local from_str = 'port:5290,wss_port:5291'
        local to_str = 'port:80,wss_port:443'
        body, c = string.gsub(body, from_str, to_str)
    end
    return body
end

function _M.api_resp_rewrite_filter(body, inner_domain, outer_domain)
    if ngx.var.arg__mt == "octopus.queryLandingPage" or
        ngx.var.arg__mt == "octopus.bulkQueryBooths" then
        body = rewrite_base64(body, function(body)
            return rewrite_domain_func(body, inner_domain, outer_domain)
        end
        )
    else
        body, _ = string.gsub(body, inner_domain, outer_domain)
    end
    return body
end

function _M.tfs_link_rewrite_filter(body, inner_domain, outer_domain)
    -- rewrite static file host
    body, _ = string.gsub(body, "jkcdn.test.pahys.net", "static.test.pajk.cn")
    return body
end

-- DO NOT USE THIS FILTER ON ANY ENVIRONMENT OTHER THAN DEVELOPMENT
-- im special handling, wss port replacement and JIDHOST must not be changed
function _M.im_rewrite_dev_filter(body, inner_domain, outer_domain)
    if ngx.re.match(ngx.var.request_uri, "cable(-shadow)?/scripts/app.*.js", "ojs") then
        -- restore JID host domain
        local from_str = 'XMPP.JIDHOST="im.test.' .. outer_domain .. '"'
        local to_str = 'XMPP.JIDHOST="im.test.' .. inner_domain .. '"'
        body, c = string.gsub(body, from_str, to_str)
        -- replace wss port 5291 to 443
        local from_str = 'XMPP.SERVICE_PORT=5291'
        local to_str = 'XMPP.SERVICE_PORT=443'
        body, c = string.gsub(body, from_str, to_str)
        -- downgrade to ws protocol
        from_str = 'PROTOCOL:"wss"'
        to_str = 'PROTOCOL:"ws"'
        body, c = string.gsub(body, from_str, to_str)
    elseif ngx.re.match(ngx.var.request_uri, "im-cs-m/js/im-cs-m.*.js", "ojs") then
        -- restore JID host domain
        local from_str = 'jid:"im.test.' .. outer_domain .. '"'
        local to_str = 'jid:"im.test.' .. inner_domain .. '"'
        body, c = string.gsub(body, from_str, to_str)
        -- replace wss port 5291 to 443
        local from_str = 'port:5290,wss_port:5291'
        local to_str = 'port:80,wss_port:443'
        body, c = string.gsub(body, from_str, to_str)
        -- downgrade to ws protocol
        from_str = 'this.port=t.wss_port,this.protocol="wss"'
        to_str = 'this.port=80,this.protocol="ws"'
        body, c = string.gsub(body, from_str, to_str)
    end
    return body
end

-- DO NOT USE THIS FILTER ON ANY ENVIRONMENT OTHER THAN DEVELOPMENT
function _M.api_resp_rewrite_dev_filter(body, inner_domain, outer_domain)
    if ngx.var.arg__mt == "octopus.queryLandingPage" or
        ngx.var.arg__mt == "octopus.bulkQueryBooths" then
        body = rewrite_base64(body, function(body)
            body = rewrite_domain_func(body, inner_domain, outer_domain)
            return downgrade_protocol_func(body)
        end
        )
    else
        body, _ = string.gsub(body, inner_domain, outer_domain)
    end
    return body
end

-- DO NOT USE THIS FILTER ON ANY ENVIRONMENT OTHER THAN DEVELOPMENT
-- downgrade https to http to ease development
function _M.https_downgrade_rewrite_filter(body, inner_domain, outer_domain)
    return downgrade_protocol_func(body)
end

return _M

-- vim: set ai nu expandtab ts=4 sw=4 tw=72 syntax=lua: