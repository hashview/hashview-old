redis: redis-server
mgmt-worker: TERM_CHILD=1 COUNT=5 QUEUE=management rake resque:workers
hashcat-worker: TERM_CHILD=1 COUNT=1 QUEUE=hashcat rake resque:work
background-worker: QUEUE=* rake resque:scheduler
web: ruby ./hashview.rb
