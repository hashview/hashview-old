#!/usr/bin/env ruby
require 'redis'

#setup redis object
redis = Redis.new

#display total hashes before insert
dbSize_start = (redis.dbSize).to_s

print "[*] " + dbSize_start + " hashes stored\r\n"

#create compatible redis protocol
def gen_redis_proto(*cmd)
    proto = ""
    proto << "*"+cmd.length.to_s+"\r\n"
    cmd.each{|arg|
        proto << "$"+arg.to_s.bytesize.to_s+"\r\n"
        proto << arg.to_s+"\r\n"
    }
    proto
end

#read pot file from first argument
potFile = File.open(ARGV[0], 'r') { |f| f.read}

print "[*] Loading " + (potFile.lines.count).to_s + " hashes\r\n"

#write protocol to new variable and feed it to redis

potFile.each_line { |line|

    line_split = line.split(":")
    hash = line_split[0].to_s
    plaintext = line_split[1].to_s
    redis.hset(hash, "plaintext:",plaintext)

}

#display added hashes and save db
dbSize = (redis.dbSize).to_s

print "[*] " + dbSize + " hashes stored\r\n"

redis.bgsave