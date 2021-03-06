require File.dirname(__FILE__) + '/../spec_helper'

JSystem = java.lang.System
JContext = javax.naming.Context

describe Trinidad::Server do

  it "always uses symbols as configuration keys" do
    server = Trinidad::Server.new({'port' => 4000})
    server.config[:port].should == 4000
  end

  it "enables catalina naming" do
    Trinidad::Server.new
    JSystem.get_property(JContext.URL_PKG_PREFIXES).should  include("org.apache.naming")
    JSystem.get_property(JContext.INITIAL_CONTEXT_FACTORY).should == "org.apache.naming.java.javaURLContextFactory"
    JSystem.get_property("catalina.useNaming").should == "true"
  end

  it "disables ssl when config param is nil" do
    server = Trinidad::Server.new
    server.ssl_enabled?.should be_false
  end

  it "disables ajp when config param is nil" do
    server = Trinidad::Server.new
    server.ajp_enabled?.should be_false
  end

  it "enables ssl when config param is a number" do
    begin
      server = Trinidad::Server.new({:ssl => {:port => 8443},
        :web_app_dir => MOCK_WEB_APP_DIR})

      server.ssl_enabled?.should be_true
      File.exist?('ssl').should be_true
    ensure
      require 'fileutils'
      FileUtils.rm_rf(File.expand_path('../../ssl', File.dirname(__FILE__)))
    end
  end

  it "enables ajp when config param is a number" do
    server = Trinidad::Server.new({:ajp => {:port => 8009}})

    server.ajp_enabled?.should be_true
  end

  it "includes a connector with https scheme when ssl is enabled" do
    server = Trinidad::Server.new({:ssl => {:port => 8443},
      :web_app_dir => MOCK_WEB_APP_DIR})

    connectors = server.tomcat.service.find_connectors
    connectors.should have(1).connector
    connectors[0].scheme.should == 'https'
  end

  it "includes a connector with protocol AJP when ajp is enabled" do
    server = Trinidad::Server.new({:ajp => {:port => 8009}})

    connectors = server.tomcat.service.find_connectors
    connectors.should have(1).connector
    connectors[0].protocol.should == 'AJP/1.3'
  end

  it "loads one application for each option present into :web_apps" do
    server = Trinidad::Server.new({
      :web_apps => {
        :mock1 => {
          :context_path => '/mock1',
          :web_app_dir => MOCK_WEB_APP_DIR
        },
        :mock2 => {
          :web_app_dir => MOCK_WEB_APP_DIR
        },
        :default => {
          :web_app_dir => MOCK_WEB_APP_DIR
        }
      }
    })

    context_loaded = server.tomcat.host.find_children
    context_loaded.should have(3).web_apps

    expected = ['/mock1', '/mock2', '/']
    context_loaded.each do |context|
      expected.delete(context.path).should == context.path
    end
  end

  it "loads the default application from the current directory if :web_apps is not present" do
    server = Trinidad::Server.new({:web_app_dir => MOCK_WEB_APP_DIR})

    default_context_should_be_loaded(server.tomcat.host.find_children)
  end

  it "removes default servlets from the application" do
    server = Trinidad::Server.new({:web_app_dir => MOCK_WEB_APP_DIR})
    app = server.tomcat.host.find_child('/')

    app.find_child('default').should be_nil
    app.find_child('jsp').should be_nil

    app.find_servlet_mapping('*.jsp').should be_nil
    app.find_servlet_mapping('*.jspx').should be_nil

    app.process_tlds.should be_false
  end

  it "uses the default HttpConnector when http is not configured" do
    server = Trinidad::Server.new({:web_app_dir => MOCK_WEB_APP_DIR})
    server.http_configured?.should be_false

    server.tomcat.connector.protocol_handler_class_name.should == 'org.apache.coyote.http11.Http11Protocol'
  end

  it "uses the NioConnector when the http configuration sets nio to true" do
    server = Trinidad::Server.new({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :http => {:nio => true}
    })
    server.http_configured?.should be_true

    server.tomcat.connector.protocol_handler_class_name.should == 'org.apache.coyote.http11.Http11NioProtocol'
  end

  it "configures NioConnector with http option values" do
    server = Trinidad::Server.new({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :http => {
        :nio => true,
        'maxKeepAliveRequests' => 4,
        'socket.bufferPool' => 1000
      }
    })
    connector = server.tomcat.connector
    connector.get_property('maxKeepAliveRequests').should == 4
    connector.get_property('socket.bufferPool').should == '1000'
  end

  it "adds the WebAppLifecycleListener to each webapp" do
    server = Trinidad::Server.new({:web_app_dir => MOCK_WEB_APP_DIR})
    app_context = server.tomcat.host.find_child('/')    

    app_context.find_lifecycle_listeners.map {|l| l.class.name }.should include('Trinidad::WebAppLifecycleListener')
  end

  it "loads application extensions from the root of the configuration" do
    server = Trinidad::Server.new({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :extensions => { :foo => {} }
    })

    app_context = server.tomcat.host.find_child('/')
    app_context.doc_base.should == 'foo_app_extension'
  end

  it "doesn't create a default keystore when the option SSLCertificateFile is present in the ssl configuration options" do
    require 'fileutils'
    FileUtils.rm_rf 'ssl'

    server = Trinidad::Server.new({
      :ssl => {
        :port => 8443,
        :SSLCertificateFile => '/usr/local/ssl/server.crt'
      },
      :web_app_dir => MOCK_WEB_APP_DIR})

    File.exist?('ssl').should be_false
  end

  def default_context_should_be_loaded(children)
    children.should have(1).web_apps
    children[0].doc_base.should == MOCK_WEB_APP_DIR
    children[0].path.should == '/'
    children[0]
  end
end
