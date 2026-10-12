#!/usr/bin/env ruby
# Deletes stale CI-created Apple Development certificates so automatic signing on a fresh
# runner can always create the one it needs (Apple caps how many an account may hold).
# Only DEVELOPMENT / IOS_DEVELOPMENT certificates whose name contains "Created via API" are
# touched; distribution certificates and ones made by hand in Xcode are left alone.
# Never fails the build: signing will report its own error if this didn't help.
require "base64"
require "json"
require "net/http"
require "openssl"

key_id = ENV.fetch("ASC_KEY_ID")
issuer = ENV.fetch("ASC_ISSUER_ID")
key_path = ENV.fetch("ASC_KEY_PATH")
dry_run = ENV["DRY_RUN"] == "1"

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def token(key_id, issuer, key_path)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer, exp: Time.now.to_i + 600, aud: "appstoreconnect-v1" }
  input = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
  der = OpenSSL::PKey::EC.new(File.read(key_path)).sign(OpenSSL::Digest.new("SHA256"), input)
  # JWT wants the raw r||s form, not DER.
  r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }
  "#{input}.#{b64(r + s)}"
end

def request(verb, path, jwt)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP.const_get(verb).new(uri)
  req["Authorization"] = "Bearer #{jwt}"
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
end

begin
  jwt = token(key_id, issuer, key_path)
  res = request("Get", "/v1/certificates?limit=200&filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT", jwt)
  abort_msg = "Could not list certificates (HTTP #{res.code}): #{res.body[0, 300]}"
  raise abort_msg unless res.code == "200"
  certs = JSON.parse(res.body)["data"]
  puts "#{certs.length} development certificate(s) on the account"
  stale = certs.select { |c| c["attributes"]["name"].to_s.include?("Created via API") }
  puts "#{stale.length} created by automatic signing"
  stale.each do |cert|
    a = cert["attributes"]
    label = "#{a['name']} (#{a['certificateType']}, expires #{a['expirationDate']})"
    if dry_run
      puts "would delete #{label}"
      next
    end
    del = request("Delete", "/v1/certificates/#{cert['id']}", jwt)
    puts "#{del.code == '204' ? 'deleted' : "FAILED #{del.code}"} #{label}"
  end
rescue => e
  puts "Skipping certificate cleanup: #{e.message}"
end
