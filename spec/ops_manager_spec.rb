require 'spec_helper'
require 'yaml'

describe OpsManager do
  let(:product_deployment_file){'product_deployment.yml'}
  let(:current_vm_name){ "ops-manager-#{current_version}"}
  let(:target){ '1.2.3.4' }
  let(:username){ 'foo' }
  let(:password){ 'bar' }
  let(:ops_manager) { described_class.new }

  let(:ops_manager_dir){ "#{ENV['HOME']}/.ops_manager" }

  before{ `rm -rf #{ops_manager_dir}` }

  it 'has a version number' do
    expect(OpsManager::VERSION).not_to be nil
  end

  describe '@set_conf' do
    describe 'when configuration has not been set' do
      before{ `rm -rf #{ops_manager_dir}` }

      it 'should write conf to the yaml' do
        expect do
          OpsManager.set_conf :foo, 'baz'
        end.to change{ OpsManager.get_conf :foo }.from(nil).to('baz')
      end
    end

    describe 'when configuration has been set' do
      before{ OpsManager.set_conf :foo, 'bar' }

      it 'should merge conf to the yaml' do
        expect do
          OpsManager.set_conf :foo, 'baz'
        end.to change{ OpsManager.get_conf :foo }.from('bar').to('baz')
      end

      it 'should warn user that the conf is being changed' do
        expect do
          OpsManager.set_conf :foo, 'baz'
        end.to output(/Changing foo to baz/).to_stdout
      end
    end
  end

  describe '@target' do
    let(:net_ping){ double(ping?: pingable?) }
    before do
      OpsManager.set_conf(:target, nil)
      allow(Net::Ping::HTTP).to receive(:new).with("https://#{target}").and_return(net_ping)
    end

    describe 'when target is pingable' do
      let(:pingable?){ true }

      it 'should set conf target' do
        expect do
          OpsManager.target(target)
        end.to change{ OpsManager.get_conf :target }.from(nil).to(target)
      end
    end

    describe 'when target is not pingable' do
      let(:pingable?){ false }

      it 'should set conf target' do
        expect do
          OpsManager.target(target)
        end.not_to change{ OpsManager.get_conf :target }
      end
    end
  end

  describe '@login' do
    it 'should set conf username' do
      expect do
        OpsManager.login('foo', 'bar')
      end.to change{ OpsManager.get_conf :username }
    end

    it 'should set conf password' do
      expect do
        OpsManager.login('foo', 'bar')
      end.to change{ OpsManager.get_conf :password }
    end
  end

  describe 'target_and_login' do
    before do
      allow(OpsManager).to receive(:target)
      allow(OpsManager).to receive(:login)
    end

    describe 'when config has credentials' do
      let(:config) do
        {
          'target' => target,
          'username' => username,
          'password' => password
        }
      end

      it 'should target' do
        expect(OpsManager).to receive(:target).with(target)
        ops_manager.target_and_login(config)
      end

      it 'should login' do
        expect(OpsManager).to receive(:login).with(username, password)
        ops_manager.target_and_login(config)
      end
    end

    describe 'when config does not have credentials' do
      let(:config)  {{}}

      it 'should not target' do
        expect(OpsManager).not_to receive(:target).with(target)
        ops_manager.target_and_login(config)
      end

      it 'should not login' do
        expect(OpsManager).not_to receive(:login).with(username, password)
        ops_manager.target_and_login(config)
      end
    end
  end

  describe 'deploy_product' do
    before do
      allow_any_instance_of(OpsManager::Product).to receive(:deploy)
      allow_any_instance_of(OpsManager).to receive(:target_and_login)
      allow_any_instance_of(OpsManager).to receive(:import_stemcell)
    end

    it 'should target_and_login' do
      expect_any_instance_of(OpsManager).to receive(:target_and_login)
      ops_manager.deploy_product(product_deployment_file)
    end

    it 'should provision stemcell' do
      expect_any_instance_of(OpsManager).to receive(:import_stemcell).with('stemcell.tgz')
      ops_manager.deploy_product(product_deployment_file)
    end

    it 'should execute a product deploy' do
      expect_any_instance_of(OpsManager::Product).to receive(:deploy)
      ops_manager.deploy_product(product_deployment_file)
    end
  end



end
