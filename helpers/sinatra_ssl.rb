# encoding utf-8
require 'webrick/https'

module Sinatra
  class Application
    def self.run!

      # Check to see if SSL cert is present, if not generate
      unless File.exist?('cert/server.crt')
        # Generate Cert
        system('openssl req -x509 -nodes -days 365 -newkey RSA:2048 -subj "/CN=US/ST=Minnesota/L=Duluth/O=potatoFactory/CN=hashview" -keyout cert/server.key -out cert/server.crt')
      end

      set :ssl_certificate, 'cert/server.crt'
      set :ssl_key, 'cert/server.key'
      set :bind, '0.0.0.0'
      set :port, '4567'

      certificate_content = File.open(ssl_certificate).read
      key_content = File.open(ssl_key).read

      server_options = {
        Host: bind,
        Port: port,
        SSLEnable: true,
        SSLCertificate: OpenSSL::X509::Certificate.new(certificate_content),
        SSLPrivateKey: OpenSSL::PKey::RSA.new(key_content)
      }

      Rack::Handler::WEBrick.run self, server_options do |server|
        [:INT, :TERM].each { |sig| trap(sig) { server.stop } }
        server.threaded = settings.threaded if server.respond_to? :threaded=
        set :running, true
      end
    end
  end
end
