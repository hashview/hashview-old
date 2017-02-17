redis: redis-server
mgmt-worker: TERM_CHILD=1 COUNT=2 QUEUE=management rake resque:workers
hashcat-worker: TERM_CHILD=1 COUNT=1 QUEUE=hashcat rake resque:work
web: ruby ./hashview.rb