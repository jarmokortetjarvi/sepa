require 'savon'
require 'nokogiri'
require 'openssl'
require 'base64'

private_key = OpenSSL::PKey::RSA.new File.read 'keys/private.pem'
cert = OpenSSL::X509::Certificate.new File.read 'keys/cert.pem'
ssl_cert = OpenSSL::X509::Certificate.new File.read 'keys/ssl_key.cer'

def load_soap_request
  f = File.open("xml_templates/soap_envelope_get_user_info.xml")
  soap_request = Nokogiri::XML(f)
  f.close
  soap_request
end

def load_application_request_signature
  f = File.open("xml_templates/application_request_signature.xml")
  application_request_signature = Nokogiri::XML(f)
  f.close
  application_request_signature
end

def load_soap_request_header
  f = File.open("xml_templates/soap_request_header_template.xml")
  soap_request_header = Nokogiri::XML(f)
  f.close
  soap_request_header
end

def load_application_request_schema
  xsd = Nokogiri::XML::Schema(File.read("xml_templates/application_request_schema.xsd"))
  xsd
end

def load_soap_envelope_schema
  xsd = Nokogiri::XML::Schema(File.read("xml_templates/soap_envelope_schema.xsd"))
  xsd
end

def process_application_request(xsd)
  #Load the application request from template
  f = File.open("xml_templates/application_request_get_user_info.xml")
  application_request = Nokogiri::XML(f)
  f.close

  # Change the customer id of the application request to Nordea's testing ID
  customer_id = application_request.at_css "CustomerId"
  customer_id.content = "11111111"

  # Set the command
  command = application_request.at_css "Command"
  command.content = "GetUserInfo"

  #Set the timestamp
  timestamp = application_request.at_css "Timestamp"
  timestamp.content = Time.now.to_time.iso8601

  # Set the environment
  environment = application_request.at_css "Environment"
  environment.content = "PRODUCTION"

  #Set the software id
  softwareid = application_request.at_css "SoftwareId"
  softwareid.content = "Sepa Transfer Library version 0.1"

  #Validate the application request
  if xsd.valid?(application_request)
    puts "Application request passed validation"
  end

  #Canonicalize the application request
  canon_application_request = application_request.canonicalize
  canon_application_request
end

def sign_application_request(application_request, application_request_signature, private_key, cert)
  #Take digest from application request, base64 code it and set it to the signature
  sha1 = OpenSSL::Digest::SHA1.new
  digestbin = sha1.digest(application_request)
  digest = Base64.encode64(digestbin)
  signature_digest = application_request_signature.at_css "DigestValue"
  signature_digest.content = digest.gsub(/\s+/, "")

  #Sign the digest with private key and base64 code it
  digest_sign = OpenSSL::Digest::SHA1.new
  signature = private_key.sign(digest_sign, digest.to_s)
  signature_base64 = Base64.encode64(signature)

  #Add the base64 coded signature to the signature element
  signature_signature = application_request_signature.at_css "SignatureValue"
  signature_signature.content = signature_base64.gsub(/\s+/, "")

  #Format the certificate and add the it to the certificate element
  cert_formatted = cert.to_s.split('-----BEGIN CERTIFICATE-----')[1].split('-----END CERTIFICATE-----')[0].gsub(/\s+/, "")
  signature_certificate = application_request_signature.at_css "X509Certificate"
  signature_certificate.content = cert_formatted

  #Convert application request to XML and add the signature element to it
  application_request_xml  = Nokogiri::XML(application_request)
  application_request_xml.root.add_child(application_request_signature.root)

  #Canonicalize the whole application request
  application_request_canon = application_request_xml.canonicalize

  #Base64 code the whole application request
  application_request_base64 = Base64.encode64(application_request_canon)
  application_request_base64

end

def process_soap_request(soap_request, application_request_base64)
  #Add the base64 coded application request to the soap envelope after removing whitespaces
  soap_request_application_request = soap_request.xpath("//mod:ApplicationRequest", 'mod' => 'http://model.bxd.fi').first
  soap_request_application_request.content = application_request_base64.gsub(/\s+/, "")

  #Add the testing sender id
  soap_request_sender_id = soap_request.xpath("//mod:SenderId", 'mod' => 'http://model.bxd.fi').first
  soap_request_sender_id.content = "11111111"

  #Add request id
  soap_request_request_id = soap_request.xpath("//mod:RequestId", 'mod' => 'http://model.bxd.fi').first
  soap_request_request_id.content = "2378764423723"

  #Add timestamp
  soap_request_timestamp = soap_request.xpath("//mod:Timestamp", 'mod' => 'http://model.bxd.fi').first
  soap_request_timestamp.content = Time.now.iso8601

  # Add language
  soap_request_language = soap_request.xpath("//mod:Language", 'mod' => 'http://model.bxd.fi').first
  soap_request_language.content = "FI"

  #Add useragent
  soap_request_useragent = soap_request.xpath("//mod:UserAgent", 'mod' => 'http://model.bxd.fi').first
  soap_request_useragent.content = "Sepa Transfer Library version 0.1"

  #Add receiver id
  soap_request_receiverid = soap_request.xpath("//mod:ReceiverId", 'mod' => 'http://model.bxd.fi').first
  soap_request_receiverid.content = "11111111A1"

  #Canonicalize the request
  soap_request.canonicalize
end

def sign_soap_request(soap_request, soap_request_header, private_key, cert, xsd)
  #Take digest from soap request, base64 code it and put it to the signature
  soap_request_xml  = Nokogiri::XML(soap_request)
  soap_request_body = soap_request_xml.xpath("//soapenv:Body", 'soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/').first
  sha1 = OpenSSL::Digest::SHA1.new
  digestbin = sha1.digest(soap_request_body)
  digest = Base64.encode64(digestbin)
  signature_digest = soap_request_header.xpath("//ds:DigestValue", 'ds' => 'http://www.w3.org/2000/09/xmldsig#').first
  signature_digest.content = digest.gsub(/\s+/, "")

  #Sign the digest with private key and base64 code it
  digest_sign = OpenSSL::Digest::SHA1.new
  signature = private_key.sign(digest_sign, digest.to_s)
  signature_base64 = Base64.encode64(signature)

  #Add the base64 coded signature to the signature element
  signature_signature = soap_request_header.xpath("//ds:SignatureValue", 'ds' => 'http://www.w3.org/2000/09/xmldsig#').first
  signature_signature.content = signature_base64.gsub(/\s+/, "")

  #Format the certificate and add the it to the certificate element
  cert_formatted = cert.to_s.split('-----BEGIN CERTIFICATE-----')[1].split('-----END CERTIFICATE-----')[0].gsub(/\s+/, "")
  signature_certificate = soap_request_header.xpath("//wsse:BinarySecurityToken", 'wsse' => 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd').first
  signature_certificate.content = cert_formatted

  #Merge the body and header of the soap envelope
  soap_request_xml  = Nokogiri::XML(soap_request)
  soap_request_header.root.add_child(soap_request_xml.xpath("//soapenv:Body", 'soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/').first)

  #Validate the whole soap
  if xsd.valid?(soap_request_header)
    puts "Soap envelope passed validation"
  end

  # Add missing namespaces
  body = soap_request_header.xpath("//soapenv:Body", 'soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/').first
  body.add_namespace 'wsu', 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd'
  body.set_attribute('wsu:Id', 'id-23633426')

  soap_request_header
end

signed_application_request = sign_application_request(process_application_request(load_application_request_schema), load_application_request_signature, private_key, cert)

processed_soap_request = process_soap_request(load_soap_request, signed_application_request)

signed_soap_request = sign_soap_request(processed_soap_request, load_soap_request_header, private_key, cert, load_soap_envelope_schema)

client = Savon.client(wsdl: "wsdl/wsdl_nordea.xml", pretty_print_xml: true, ssl_version: :SSLv3, ssl_cert_file: "keys/ssl_key.cer")

response = client.call(:get_user_info, xml: signed_soap_request.to_xml)
