wrk.method = "GET"
--wrk.headers["Host"]="baike.baidu.com"
wrk.headers["Host"]="wrktest.baidu.com"
--wrk.headers["Host"]="perf_inqa.baidu.com"
--wrk.headers["Accept-encoding"]="gzip"
--wrk.headers["'Connection"]="Close"
function response(status,headers,body)
    if status ~= 200 then
    	--wrk.thread:stop()
    end
end
