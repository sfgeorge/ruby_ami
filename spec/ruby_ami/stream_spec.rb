# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe Stream do
    let(:server_port) { 50000 - rand(1000) }

    def client
      @client ||= double('Client')
    end

    before do
      def client.message_received(message)
        @messages ||= Queue.new
        @messages << message
      end

      def client.messages
        @messages
      end
    end

    let :client_messages do
      messages = []
      messages << client.messages.pop until client.messages.empty?
      messages
    end

    let(:username) { nil }
    let(:password) { nil }

    def mocked_server(times = nil, fake_client = nil, &block)
      mock_target = MockServer.new
      expect(mock_target).to receive(:receive_data).send(*(times ? [:exactly, times] : [:at_least, 1]), &block)
      s = ServerMock.new '127.0.0.1', server_port, mock_target
      @stream = Stream.new '127.0.0.1', server_port, username, password, lambda { |m| client.message_received m }
      @stream.async.run
      fake_client.call if fake_client.respond_to? :call
      Timeout.timeout 5 do
        Celluloid::Actor.join s
        Celluloid::Actor.join @stream
      end
    rescue Timeout::Error
    end

    before { @sequence = 1 }

    describe "after connection" do
      it "should be started" do
        mocked_server 0, -> { expect(@stream.started?).to be true }
        expect(client_messages).to eq([
          Stream::Connected.new,
          Stream::Disconnected.new,
        ])
      end

      it "stores the reported AMI version" do
        mocked_server(1, lambda {
          @stream.send_action('Command') # Just to get the server kicked in to replying using the below block
          expect(@stream.version).to eq('2.8.0')
        }) do |val, server|
          server.send_data "Asterisk Call Manager/2.8.0\n"

          # Just to unblock the above command before the actor shuts down
          server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Recording started

          EVENT
        end
      end

      it "can send an action" do
        mocked_server(1, lambda { @stream.send_action('Command') }) do |val, server|
          expect(val).to eq <<-ACTION
Action: command\r
ActionID: #{RubyAMI.new_uuid}\r
\r
        ACTION

          server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Recording started

          EVENT
        end
      end

      it "can send an action with headers" do
        mocked_server(1, lambda { @stream.send_action('Command', 'Command' => 'RECORD FILE evil') }) do |val, server|
          expect(val).to eq <<-ACTION
Action: command\r
ActionID: #{RubyAMI.new_uuid}\r
Command: RECORD FILE evil\r
\r
        ACTION

          server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Recording started

          EVENT
        end
      end

      it "can process an action with a Response: Follows result" do
        action_id = RubyAMI.new_uuid
        response = nil
        mocked_server(1, lambda { response = @stream.send_action('Command', 'Command' => 'dialplan add extension 1,1,AGI,agi:async into adhearsion-redirect') }) do |val, server|
          expect(val).to eq <<-ACTION
Action: command\r
ActionID: #{action_id}\r
Command: dialplan add extension 1,1,AGI,agi:async into adhearsion-redirect\r
\r
          ACTION

          server.send_data <<-EVENT
Response: Follows
Privilege: Command
ActionID: #{action_id}
Extension '1,1,AGI(agi:async)' added into 'adhearsion-redirect' context
--END COMMAND--

          EVENT
        end

        expected_response = Response.new 'Privilege' => 'Command', 'ActionID' => action_id
        expected_response.text_body = %q{Extension '1,1,AGI(agi:async)' added into 'adhearsion-redirect' context}
        expect(response).to eq(expected_response)
      end

      context "with a username and password set" do
        let(:username) { 'fred' }
        let(:password) { 'jones' }

        it "should log itself in" do
          mocked_server(1, lambda { }) do |val, server|
            expect(val).to eq <<-ACTION
Action: login\r
ActionID: #{RubyAMI.new_uuid}\r
Username: fred\r
Secret: jones\r
Events: On\r
\r
          ACTION

            server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Authentication accepted

            EVENT
          end
        end
      end
    end

    it 'sends events to the client when the stream is ready' do
      mocked_server(1, lambda { @stream.send_data 'Foo' }) do |val, server|
        server.send_data <<-EVENT
Event: Hangup
Channel: SIP/101-3f3f
Uniqueid: 1094154427.10
Cause: 0

        EVENT
      end

      expect(client_messages).to eq([
        Stream::Connected.new,
        Event.new('Hangup', 'Channel' => 'SIP/101-3f3f', 'Uniqueid' => '1094154427.10', 'Cause' => '0'),
        Stream::Disconnected.new,
      ])
    end

    describe 'when a response is received' do
      it 'should be returned from #send_action' do
        response = nil
        mocked_server(1, lambda { response = @stream.send_action 'Command', 'Command' => 'RECORD FILE evil' }) do |val, server|
          server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Recording started

          EVENT
        end

        expect(response).to eq(Response.new('ActionID' => RubyAMI.new_uuid, 'Message' => 'Recording started'))
      end

      it 'should handle disconnect as a Response' do
        response = nil
        mocked_server(1, lambda { response = @stream.send_action 'Logoff' }) do |val, server|
          server.send_data <<-EVENT
Response: Goodbye
ActionID: #{RubyAMI.new_uuid}
Message: Thanks for all the fish.

          EVENT
        end

        expect(response).to eq(Response.new('ActionID' => RubyAMI.new_uuid, 'Message' => 'Thanks for all the fish.'))
      end

      describe 'when it is an error' do
        describe 'when there is no error handler' do
          it 'should be raised by #send_action, but not kill the stream' do
            send_action = lambda do
              expect { @stream.send_action 'status' }.to raise_error(RubyAMI::Error, 'Action failed')
              expect(@stream).to be_alive
            end

            mocked_server(1, send_action) do |val, server|
              server.send_data <<-EVENT
Response: Error
ActionID: #{RubyAMI.new_uuid}
Message: Action failed

              EVENT
            end
          end
        end

        describe 'when there is an error handler' do
          it 'should call the error handler' do
            error_handler = lambda { |resp| expect(resp).to be_a_kind_of RubyAMI::Error }

            send_action = lambda do
              expect { @stream.send_action 'status', {}, error_handler }.to_not raise_error
              expect(@stream).to be_alive
            end

            mocked_server(1, send_action) do |val, server|
              server.send_data <<-EVENT
Response: Error
ActionID: #{RubyAMI.new_uuid}
Message: Action failed

              EVENT
            end
          end
        end
      end

      describe 'for a causal action' do
        let :expected_events do
          [
            Event.new('PeerEntry', 'ActionID' => RubyAMI.new_uuid, 'Channeltype' => 'SIP', 'ObjectName' => 'usera'),
            Event.new('PeerlistComplete', 'ActionID' => RubyAMI.new_uuid, 'EventList' => 'Complete', 'ListItems' => '2')
          ]
        end

        let :expected_response do
          Response.new('ActionID' => RubyAMI.new_uuid, 'Message' => 'Events to follow').tap do |response|
            response.events = expected_events
          end
        end

        it "should return the response with events" do
          response = nil
          mocked_server(1, lambda { response = @stream.send_action 'sippeers' }) do |val, server|
            server.send_data <<-EVENT
Response: Success
ActionID: #{RubyAMI.new_uuid}
Message: Events to follow

Event: PeerEntry
ActionID: #{RubyAMI.new_uuid}
Channeltype: SIP
ObjectName: usera

Event: PeerlistComplete
EventList: Complete
ListItems: 2
ActionID: #{RubyAMI.new_uuid}

            EVENT
          end

          expect(response).to eq(expected_response)
        end
      end
    end

    it 'puts itself in the stopped state and fires a disconnected event when unbound' do
      mocked_server(1, lambda { @stream.send_data 'Foo' }) do |val, server|
        expect(@stream.stopped?).to be false
      end
      expect(@stream.alive?).to be false
      expect(client_messages).to eq([
        Stream::Connected.new,
        Stream::Disconnected.new,
      ])
    end
  end

  describe Stream::Connected do
    it "has a name matching the class" do
      expect(subject.name).to eq('RubyAMI::Stream::Connected')
    end
  end

  describe Stream::Disconnected do
    it "has a name matching the class" do
      expect(subject.name).to eq('RubyAMI::Stream::Disconnected')
    end
  end
end
