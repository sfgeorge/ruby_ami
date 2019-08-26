# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe Event do
    subject { described_class.new 'Hangup' }

    describe "#receipt_time" do
      before do
        @now = DateTime.now
        allow(DateTime).to receive_messages now: @now
      end

      it "should be the time the object was created (event receipt time)" do
        expect(subject.receipt_time).to eq(@now)
      end
    end

    context "when the event has a timestamp" do
      subject { described_class.new 'Hangup', 'Timestamp' => '1393368380.572575' }

      describe "#timestamp" do
        it "should be a time object representing the event's timestamp (assuming UTC)" do
          expect(subject.timestamp).to eq(DateTime.new(2014, 2, 25, 22, 46, 20))
        end
      end

      describe "#best_time" do
        it "should be the timestamp" do
          expect(subject.best_time).to eq(subject.timestamp)
        end
      end
    end

    context "when the event does not have a timestamp" do
      describe "#timestamp" do
        it "should be nil" do
          expect(subject.timestamp).to be_nil
        end
      end

      describe "#best_time" do
        it "should be the receipt_time" do
          expect(subject.best_time).to eq(subject.receipt_time)
        end
      end
    end

    describe "equality" do
      context "with the same name and the same headers" do
        let :event1 do
          Event.new 'Hangup',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '0'
        end

        let :event2 do
          Event.new 'Hangup',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '0'
        end

        it "should be equal" do
          expect(event1).to eq(event2)
        end
      end

      context "with a different name and the same headers" do
        let :event1 do
          Event.new 'Hangup',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '0'
        end

        let :event2 do
          Event.new 'Foo',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '0'
        end

        it "should not be equal" do
          expect(event1).not_to eq(event2)
        end
      end

      context "with the same name and different headers" do
        let :event1 do
          Event.new 'Hangup',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '0'
        end

        let :event2 do
          Event.new 'Hangup',
            'Channel' => 'SIP/101-3f3f',
            'Uniqueid' => '1094154427.10',
            'Cause' => '1'
        end

        it "should not be equal" do
          expect(event1).not_to eq(event2)
        end
      end
    end

    describe "#[]= Header assignment" do
      shared_examples 'not decoding a value' do
        it 'does not decode the value' do
          expect(event[header_key]).to eq(raw_header_value)
        end
      end

      let(:raw_header_value) { '\\? Que \\?'.freeze }

      let(:raw_headers) do
        {
          'Channel'  => 'SIP/101-3f3f',
          header_key => raw_header_value
        }
      end

      let(:event) do
        Event.new(event_name).tap do |event|
          raw_headers.each { |key, raw_value| event[key] = raw_value }
        end
      end

      context 'when the event name is not "VarSet"' do
        let(:event_name) { 'Hangup' }

        context 'and the header key is "Value"' do
          let(:header_key) { 'Value' }
          it_behaves_like 'not decoding a value'
        end
      end

      context 'when the event name is "VarSet"' do
        let(:event_name) { 'VarSet' }

        context 'and the header key is not "Value"' do
          let(:header_key) { 'Uniqueid' }
          it_behaves_like 'not decoding a value'
        end

        context 'and the header key is "Value"' do
          let(:header_key) { 'Value' }

          {
            '\\a Que \\a'   => "\a Que \a",
            '\\b Que \\b'   => "\b Que \b",
            '\\f Que \\f'   => "\f Que \f",
            '\\n Que \\n'   => "\n Que \n",
            '\\r Que \\r'   => "\r Que \r",
            '\\t Que \\t'   => "\t Que \t",
            '\\v Que \\v'   => "\v Que \v",
            '\\\\ Que \\\\' => '\\ Que \\',
            "\\' Que \\'"   => "' Que '",
            '\\" Que \\"'   => '" Que "',
            '\\? Que \\?'   => '? Que ?',
            '\\ ? Que \\ ?' => '\\ ? Que \\ ?',
            '\\\\\\\\\\\\'  => '\\\\\\',
            '\\\\\\\\\\?'   => '\\\\?',
            '\\a\\b\\"\\?'  => "\a\b\"?",
          }.each do |raw_value, expected_value|
            context "the raw value #{raw_value.inspect}" do
              let(:raw_header_value) { raw_value }
              it 'is decoded' do
                expect(event[header_key]).to eq(expected_value)
              end
            end
          end
        end
      end
    end
  end # Event
end # RubyAMI
