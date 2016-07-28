require 'webrick/https'

module Sinatra
  class Application
    def self.run!
      certificate_content = File.open(ssl_certificate).read
      key_content = File.open(ssl_key).read

      server_options = {
        :Host => bind,
        :Port => port,
        :SSLEnable => true,
        :SSLCertificate => OpenSSL::X509::Certificate.new(certificate_content),
        :SSLPrivateKey => OpenSSL::PKey::RSA.new(key_content)
      }

      Rack::Handler::WEBrick.run self, server_options do |server|
        [:INT, :TERM].each { |sig| trap(sig) { server.stop } }
        server.threaded = settings.threaded if server.respond_to? :threaded=
        set :running, true
      end
    end
  end
end
