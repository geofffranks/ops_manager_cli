require 'spec_helper'
require "ops_manager/appliance_deployment"
require 'yaml'

describe OpsManager::ApplianceDeployment do
  let(:appliance_deployment){ described_class.new(config_file) }
  let(:target){'1.2.3.4'}
  let(:current_version){ OpsManager::Semver.new('1.5.5') }
  let(:desired_version){ OpsManager::Semver.new('1.5.5') }
  let(:pivnet_api){ object_double(OpsManager::Api::Pivnet.new) }
  let(:opsman_api){ object_double(OpsManager::Api::Opsman.new) }
  let(:username){ 'foo' }
  let(:password){ 'foo' }
  let(:pivnet_token){ 'asd123' }
  let(:installation){ double.as_null_object }
  let(:target){ '1.2.3.4' }
  let(:config_file){ 'ops_manager_deployment.yml' }
  let(:config) do
    double('config',
           name: 'ops-manager',
           desired_version: desired_version.to_s,
           ip: target,
           password: password,
           username: username,
           pivnet_token: pivnet_token)
  end

  before do
    OpsManager.set_conf(:target, ENV['TARGET'] || target)
    OpsManager.set_conf(:username, ENV['USERNAME'] || 'foo')
    OpsManager.set_conf(:password, ENV['PASSWORD'] || 'bar')

    allow(OpsManager::Api::Pivnet).to receive(:new).and_return(pivnet_api)
    allow(OpsManager::Api::Opsman).to receive(:new).and_return(opsman_api)
    allow(OpsManager::InstallationRunner).to receive(:trigger!).and_return(installation)

    allow(appliance_deployment).to receive(:current_version).and_return(current_version)
    allow(appliance_deployment).to receive(:config).and_return(config)
    allow(appliance_deployment).to receive(:parsed_installation_settings).and_return({})
  end

  describe 'initialize' do
    it 'should set config file' do
      expect(appliance_deployment.config_file).to eq(config_file)
    end
  end

  %w{ stop_current_vm deploy_vm }.each do |m|
    describe m do
      it 'should raise not implemented error' do
        expect{ appliance_deployment.send(m) }.to raise_error(NotImplementedError)
      end
    end
  end

  describe '#deploy' do
    it 'Should perform in the right order' do
      %i( deploy_vm).each do |method|
        expect(appliance_deployment).to receive(method).ordered
      end
      appliance_deployment.deploy
    end
  end

  describe 'upgrade' do
    subject(:upgrade){ appliance_deployment.upgrade }
    before do
      %i( get_installation_assets get_installation_settings
         get_diagnostic_report ).each do |m|
           allow(opsman_api).to receive(m)
         end

         %i( download_current_stemcells
            stop_current_vm deploy upload_installation_assets
            wait_for_uaa provision_stemcells).each do |m|
              allow(appliance_deployment).to receive(m)
            end
    end

    it 'Should perform in the right order' do
      %i( get_installation_assets download_current_stemcells
         stop_current_vm deploy upload_installation_assets
         wait_for_uaa provision_stemcells).each do |m|
           expect(appliance_deployment).to receive(m).ordered
         end
         upgrade
    end

    it 'should trigger installation' do
      expect(OpsManager::InstallationRunner).to receive(:trigger!)
      upgrade
    end

    it 'should wait for installation' do
      expect(installation).to receive(:wait_for_result)
      upgrade
    end
  end

  describe '#list_current_stemcells' do
    subject(:list_current_stemcells){ appliance_deployment.list_current_stemcells }

    let(:version){ "3062" }
    let(:other_version){ "3063" }
    let(:installation_settings) do
      {
        "products" => [
          { "stemcell": { "version" => version       } },
          { "stemcell": { "version" => other_version } },
        ]
      }
    end


    before do
      allow(appliance_deployment).to receive(:get_installation_settings)
        .and_return(double(status_code: 200, body: installation_settings.to_json))
    end

    describe 'when installation_settings are present' do
      it 'should return list of current stemcells' do
        expect(list_current_stemcells).to eq( [ version, other_version ])
      end
    end
  end

  describe '#find_stemcell_release' do
    subject(:find_stemcell_release){ appliance_deployment.find_stemcell_release(stemcell_version) }
    let(:product_releases_response) do
      {
        'releases' => [
          { 'id' => 1,                'version' => '3000.0'},
          { 'id' => 2,                'version' => '3000.2'},
          { 'id' => 3,                'version' => '3000.3'},
          { 'id' => 4,                'version' => '3001.0'},
        ].shuffle
      }
    end

    before do
      allow(appliance_deployment).to receive(:get_product_releases)
        .with('stemcells')
        .and_return(double(status_code: 200, body: product_releases_response.to_json))
    end

    describe 'when exact version is available' do
      let(:stemcell_version){ '3000.0' }

      it 'should return the correct release_id' do
        expect(find_stemcell_release).to eq(1)
      end
    end

    describe 'when exact version not available' do
      let(:stemcell_version){ '3000.1' }

      it 'should return the newest minor available release_id' do
        expect(find_stemcell_release).to eq(3)
      end
    end
  end

  describe '#find_stemcell_file' do
    subject(:find_stemcell_file){ appliance_deployment.find_stemcell_file(1, /vsphere/) }

    let(:stemcell_version){ "3062" }
    let(:product_file_id){ 1 }
    let(:other_product_file_id){ 2 }
    let(:product_files_response) do
      {
        "product_files" => [
          {
            "id"              => product_file_id,
            "aws_object_key"  => "product_files/Pivotal-CF/bosh-stemcell-#{stemcell_version}-vsphere-esxi-ubuntu-trusty-go_agent.tgz",
          },
          {
            "id"              => other_product_file_id,
            "aws_object_key"  => "product_files/Pivotal-CF/bosh-stemcell-#{stemcell_version}-vcloud-esxi-ubuntu-trusty-go_agent.tgz",
          }
        ].shuffle
      }
    end

    before do
      allow(appliance_deployment).to receive(:get_product_release_files)
        .with('stemcells', 1)
        .and_return(double(status_code: 200, body: product_files_response.to_json))
    end

    it 'should return the release_id of the provided stemcell version' do
      expect(find_stemcell_file).to eq(
        [
          product_file_id,
          "bosh-stemcell-#{stemcell_version}-vsphere-esxi-ubuntu-trusty-go_agent.tgz",
        ]
      )
    end
  end



  describe '#download_current_stemcells' do
    subject(:download_current_stemcells){ appliance_deployment.download_current_stemcells }
    let(:current_stemcells){ ["3062.0" , "3063.0" ] }
    let(:release_id){ rand(1000..9999) }
    let(:file_id)   { rand(1000..9999) }
    let(:stemcell_filepath){ "bosh-stemcell-3062.0-vcloud-esxi-ubuntu-trusty-go_agent.tgz" }

    before do
      allow(appliance_deployment).tap do |ad|
        ad.to receive(:list_current_stemcells).and_return(current_stemcells)
        ad.to receive(:find_stemcell_release).and_return(release_id)
        ad.to receive(:find_stemcell_file).with(release_id, /vsphere/).and_return([file_id, stemcell_filepath])
        ad.to receive(:accept_product_release_eula)
        ad.to receive(:download_product_release_file)
      end
    end

    it 'should download all stemcell' do
      expect(appliance_deployment).to receive(:download_product_release_file)
        .with('stemcells', release_id, file_id, write_to: "/tmp/current_stemcells/#{stemcell_filepath}" ).twice
      download_current_stemcells
    end

    it 'should accept product release eulas' do
      expect(appliance_deployment).to receive(:accept_product_release_eula).with('stemcells', release_id)
      download_current_stemcells
    end
  end

  describe '#provision_stemcells' do
    subject(:provision_stemcells){ appliance_deployment.provision_stemcells }

    before do
      allow(Dir).to receive(:glob).with('/tmp/current_stemcells/*')
        .and_return([
          '/tmp/current_stemcells/stemcell-1.tgz',
          '/tmp/current_stemcells/stemcell-2.tgz',
      ])
      allow(opsman_api).to receive(:reset_access_token)
    end

    it 'should upload all the stemcells in /tmp/current_stemcells' do
      expect(opsman_api).to receive(:import_stemcell)
        .with('/tmp/current_stemcells/stemcell-1.tgz')
      expect(opsman_api).to receive(:import_stemcell)
        .with('/tmp/current_stemcells/stemcell-2.tgz')
      provision_stemcells
    end

    it 'should reset the opsman token before running imports' do
      expect(opsman_api).to receive(:reset_access_token).ordered
      expect(opsman_api).to receive(:import_stemcell).ordered.twice
      provision_stemcells
    end
  end

  describe '#wait_for_uaa' do
    subject(:wait_for_uaa){ appliance_deployment.wait_for_uaa }

    before do
      allow(appliance_deployment).to receive(:sleep)
    end


    describe 'when uaa is available' do
      before do
        allow(opsman_api).to receive(:get_ensure_availability)
          .and_return(double( code:'302', body:'You are being /auth/cloudfoundry redirected'))
      end

      it 'should exit successfully' do
        expect(opsman_api).to receive(:get_ensure_availability)
        wait_for_uaa
      end
    end

    describe 'when uaa is not available yet' do
      before do
        allow(opsman_api).to receive(:get_ensure_availability)
          .and_return(
            double( code:'503', body:'503 Bad Gateway'),
            double( code:'302', body:'Ops Manager Setup'),
            double( code:'200', body:'Waiting for authentication system to start...'),
            double( code:'302', body:'You are being /auth/cloudfoundry redirected')
        )
      end

      it 'should wait until uaa is ready' do
        expect(opsman_api).to receive(:get_ensure_availability).exactly(4).times
        wait_for_uaa
      end
    end
  end

  describe '#provision_stemcells' do
    it 'should upload stemcells in /tmp/stemcells/' do
    end
  end

  describe 'current_version' do
    before do
      allow(appliance_deployment).to receive(:current_version).and_call_original
      allow(appliance_deployment).to receive(:get_diagnostic_report).and_return(diagnostic_report)
    end

    it 'should return an OpsManager::Semver'

    describe 'when version ends in .0' do
      let(:diagnostic_report) do
        double(body: { "versions" => { "release_version" => "1.8.2.0" } }.to_json)
      end

      it 'should return successfully' do
        expect(appliance_deployment.current_version.to_s).to eq("1.8.2")
      end
    end

    describe 'describe when diagnostic_report is nil' do
      let(:diagnostic_report) { nil }

      it 'should return empty Semver' do
        expect(appliance_deployment.current_version).to be_empty
      end
    end
  end

  describe 'run' do
    before do
      %i( deploy create_first_user upgrade ).each do |m|
        allow(appliance_deployment).to receive(m)
      end

      %i( target ).each do |m|
        allow(opsman_api).to receive(m)
      end
    end
    subject(:run){ appliance_deployment.run }

    describe 'when no ops-manager has been deployed' do
      let(:current_version){ OpsManager::Semver.new('') }

      it 'performs a deployment' do
        expect(appliance_deployment).to receive(:deploy)
        expect(appliance_deployment).to receive(:create_first_user)
        expect do
          run
        end.to output(/No OpsManager deployed at #{target}. Deploying .../).to_stdout
      end

      it 'does not performs an upgrade' do
        expect(appliance_deployment).to_not receive(:upgrade)
        expect do
          run
        end.to output(/No OpsManager deployed at #{target}. Deploying .../).to_stdout
      end
    end

    describe 'when ops-manager has been deployed and current and desired version match' do
      let(:desired_version){ current_version }
        let(:pending_changes_response){ { "product_changes": [] }}

      before do
        allow(appliance_deployment).to receive(:get_pending_changes)
          .and_return(double(status_code: 200, body: pending_changes_response.to_json))
      end
      it 'does not performs a deployment' do
        expect(appliance_deployment).to_not receive(:deploy)
        expect do
          run
        end.to output(/OpsManager at #{target} version is already #{current_version.to_s}. Skiping .../).to_stdout
      end

      it 'does not performs an upgrade' do
        expect(appliance_deployment).to_not receive(:upgrade)
        expect do
          run
        end.to output(/OpsManager at #{target} version is already #{current_version.to_s}. Skiping .../).to_stdout
      end

      describe 'when there are pending changes' do
        let(:pending_changes_response){ {"product_changes": [{ "guid": "cf" }]} }

        it 'should apply changes' do
          expect(OpsManager::InstallationRunner).to receive(:trigger!)
          expect do
            run
          end.to output(/OpsManager at #{target} version has pending changes. Applying changes.../).to_stdout
        end
      end
    end

    describe 'when current version is older than desired version' do
      let(:current_version){ OpsManager::Semver.new('1.4.2') }
      let(:desired_version){ OpsManager::Semver.new('1.4.11') }

      it 'performs an upgrade' do
        expect(appliance_deployment).to receive(:upgrade)
        expect do
          run
        end.to output(/OpsManager at #{target} version is #{current_version.to_s}. Upgrading to #{desired_version.to_s} .../).to_stdout
      end

      it 'does not performs a deployment' do
        expect(appliance_deployment).to_not receive(:deploy)
        expect do
          run
        end.to output(/OpsManager at #{target} version is #{current_version}. Upgrading to #{desired_version.to_s}.../).to_stdout
      end
    end
  end

  describe 'create_first_user' do
    describe 'when first try fails' do
      let(:error_response){ double({ code: 502 }) }
      let(:success_response){ double({ code: 200 }) }
      before { allow(appliance_deployment).to receive(:create_user).and_return(error_response, success_response) }

      it 'should retry until success' do
        expect(appliance_deployment).to receive(:create_user).twice
        appliance_deployment.create_first_user
      end
    end
  end
end
