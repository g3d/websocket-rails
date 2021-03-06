require "spec_helper"

module WebsocketRails

  describe ".users" do
    before do
      Synchronization.stub(:find_user)
      Synchronization.stub(:register_user)
      Synchronization.stub(:destroy_user)
    end

    it "returns the global instance of UserManager" do
      WebsocketRails.users.should be_a UserManager
    end

    context "when synchronization is enabled" do
      before do
        WebsocketRails.stub(:synchronize?).and_return(true)
      end

      context "and the user is connected to a different worker" do
        before do
          user_attr = {name: 'test', email: 'test@test.com'}
          Synchronization.stub(:find_user).and_return(user_attr)
        end

        it "publishes the event to redis" do
          Synchronization.should_receive(:publish) do |event|
            event.user_id.should == "remote"
          end

          WebsocketRails.users["remote"].send_message :test, :data
        end

        it "instantiates a user object pulled from redis" do
          remote = WebsocketRails.users["remote"]

          remote.class.should == UserManager::RemoteConnection
          remote.user.class.should == User
          remote.user.name.should == 'test'
          remote.user.persisted?.should == true
        end
      end
    end
  end

  describe UserManager do

    before do
      Synchronization.stub(:find_user)
      Synchronization.stub(:register_user)
      Synchronization.stub(:destroy_user)
    end

    let(:dispatcher) { double('dispatcher').as_null_object }
    let(:connection) do
      connection = double('Connection')
      connection.stub(:id).and_return(1)
      connection.stub(:user_identifier).and_return('Juanita')
      connection.stub(:dispatcher).and_return(dispatcher)
      connection
    end

    describe "#[]=" do
      it "store's a reference to a connection in the user's hash" do
        subject["username"] = connection
        subject.users["username"].connections.first.should == connection
      end

      context "user has no existing connections" do
        it "dispatches websocket_rails.user_connected" do
          connection.dispatcher.stub(:dispatch) do |dispatch_event|
            # Make sure that we add the LocalConnection before the event
            # is dispatched because a consumer could try to immediately send
            # a message to the connecting user
            subject["username"].should be_a UserManager::LocalConnection

            dispatch_event.data[:identifier].should eq("username")
            dispatch_event.is_internal?.should be true
            dispatch_event.name.should eq(:user_connected)
          end

          subject["username"] = connection
        end
      end

      context "user has an existing connection" do
        before do
          subject["username"] = connection
        end

        it "doesn't dispatch websocket_rails.user_connected" do
          connection.dispatcher.should_not_receive(:dispatch)
          subject["username"] = connection
        end
      end
    end

    describe "#[]" do
      before do
        subject["username"] = connection
      end

      context "when passed a known user identifier" do
        it "returns that user's connection" do
          subject["username"].connections.first.should == connection
        end
      end
    end

    describe "#delete" do
      before do
        subject["Juanita"] = connection
      end

      it "deletes the connection from the users hash" do
        subject.delete(connection)
        subject["Juanita"].should be_a UserManager::MissingConnection
      end

      context "user has exactly one existing connection" do
        it "dispatches websocket_rails.user_disconnected" do
          connection.dispatcher.should_receive(:dispatch) do |dispatch_event|
            # Make sure that we delete the LocalConnection before the event
            # is dispatched
            subject["Juanita"].should be_a UserManager::MissingConnection

            dispatch_event.data[:identifier].should eq("Juanita")
            dispatch_event.is_internal?.should be true
            dispatch_event.name.should eq(:user_disconnected)
          end

          subject.delete(connection)
        end
      end

      context "user has multiple existing connection" do
        before do
          subject["Juanita"] = double('Connection')
        end

        it "doesn't dispatch websocket_rails.user_disconnected" do
          connection.dispatcher.should_not_receive(:dispatch)
          subject.delete(connection)
        end
      end
    end

    describe "#each" do
      before do
        subject['Juanita'] = connection
      end

      context "when synchronization is disabled" do
        before do
          WebsocketRails.stub(:synchronize?).and_return false
        end

        it "passes each local connection to the given block" do
          subject.each do |conn|
            connection.should == conn.connections.first
          end
        end
      end

      context "when synchronization is enabled" do
        before do
          WebsocketRails.stub(:synchronize?).and_return true

          user_attr = {name: 'test', email: 'test@test.com'}.to_json
          Synchronization.stub(:all_users).and_return 'test' => user_attr
        end

        it "passes each remote connection to the given block" do
          subject.each do |conn|
            conn.class.should == UserManager::RemoteConnection
            conn.user.class.should == User
            conn.user.name.should == 'test'
            conn.user.email.should == 'test@test.com'
          end
        end
      end
    end

    describe "#map" do
      before do
        subject['Juanita'] = connection
      end

      context "when synchronization is disabled" do
        before do
          WebsocketRails.stub(:synchronize?).and_return false
        end

        it "passes each local connection to the given block and collects the results" do
          results = subject.map do |conn|
            [conn, true]
          end
          results.count.should == 1
          results[0][0].connections.count.should == 1
        end
      end

      context "when synchronization is enabled" do
        before do
          WebsocketRails.stub(:synchronize?).and_return true

          user_attr = {name: 'test', email: 'test@test.com'}.to_json
          Synchronization.stub(:all_users).and_return 'test' => user_attr
        end

        it "passes each remote connection to the given block and collects the results" do
          results = subject.map do |conn|
            [conn, true]
          end
          results.count.should == 1
          results[0].first.class.should == UserManager::RemoteConnection
        end
      end
    end
  end
end
