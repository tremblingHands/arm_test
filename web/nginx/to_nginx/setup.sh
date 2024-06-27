rm /usr/local/nginx -rf

#tar zxf nginx-1.22.1.tar.gz
cd nginx-1.22.1

#compile
./configure --without-http_rewrite_module --with-http_ssl_module --with-http_stub_status_module --with-http_v2_module  --with-cc-opt='-O3 -flto'
make -j8
make install

cd ..
cp ./cert /usr/local/nginx/ -rf
rm /usr/local/nginx/conf/nginx.conf -rf
cp ./nginx.conf /usr/local/nginx/conf/ -rf
cp ./0kb.bin /usr/local/nginx/html/
cp ./9kb.bin /usr/local/nginx/html/

nginxproc=`ps auxf | grep -v grep | grep nginx`
echo "$nginxproc"
if ps -ef | grep -v grep | grep "nginx: worker process" >/dev/null
then
    #nginx is running
    expect <<EOF
        set timeout 30
        spawn /usr/local/nginx/sbin/nginx -s reload
        expect "Enter PEM pass phrase" { send "0000\\r" }
        send '\\n"
        expect eof
EOF

else
    #nginx is not running
    expect <<EOF
	  set timeout 30
	  spawn /usr/local/nginx/sbin/nginx
	  expect "Enter PEM pass phrase" { send "0000\\r" }
	  send '\\n"
	  expect eof
EOF
fi

ps axo pid,cmd,psr | grep nginx | grep -v grep

