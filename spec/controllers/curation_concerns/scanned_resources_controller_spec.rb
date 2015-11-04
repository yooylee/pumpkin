# Generated via
#  `rails generate curation_concerns:work ScannedResource`
require 'rails_helper'

describe CurationConcerns::ScannedResourcesController do
  let(:user) { FactoryGirl.create(:user) }
  let(:scanned_resource) { FactoryGirl.create(:scanned_resource, user: user, title: ['Dummy Title']) }
  let(:reloaded) { scanned_resource.reload }

  describe "create" do
    let(:user) { FactoryGirl.create(:admin) }
    before do
      sign_in user
    end
    context "when given a bib id", vcr: { cassette_name: 'bibdata', allow_playback_repeats: true } do
      let(:scanned_resource_attributes) do
        FactoryGirl.attributes_for(:scanned_resource).merge(
          source_metadata_identifier: "2028405"
        )
      end
      it "updates the metadata" do
        post :create, scanned_resource: scanned_resource_attributes
        s = ScannedResource.last
        expect(s.title).to eq ['The Giant Bible of Mainz; 500th anniversary, April fourth, fourteen fifty-two, April fourth, nineteen fifty-two.']
      end
    end
    context "when given a non-existent bib id", vcr: { cassette_name: 'bibdata_not_found', allow_playback_repeats: true } do
      let(:scanned_resource_attributes) do
        FactoryGirl.attributes_for(:scanned_resource).merge(
          source_metadata_identifier: "0000000"
        )
      end
      it "receives an error" do
        expect do
          post :create, scanned_resource: scanned_resource_attributes
        end.not_to change { ScannedResource.count }
        expect(response.status).to be 500
        expect(flash[:alert]).to eq("Error retrieving metadata for '0000000'")
      end
    end

    context "when given a parent" do
      let(:parent) { FactoryGirl.create(:multi_volume_work, user: user) }
      let(:scanned_resource_attributes) do
        FactoryGirl.attributes_for(:scanned_resource).except(:source_metadata_identifier)
      end
      it "creates and indexes its parent" do
        post :create, scanned_resource: scanned_resource_attributes, parent_id: parent.id
        solr_document = ActiveFedora::SolrService.query("id:#{assigns[:curation_concern].id}").first

        expect(solr_document["ordered_by_ssim"]).to eq [parent.id]
      end
    end
  end

  describe "#manifest" do
    let(:solr) { ActiveFedora.solr.conn }
    let(:user) { FactoryGirl.create(:user) }
    context "when requesting JSON" do
      render_views
      before do
        sign_in user
      end
      it "builds a manifest" do
        resource = FactoryGirl.build(:scanned_resource)
        resource_2 = FactoryGirl.build(:scanned_resource)
        allow(resource).to receive(:id).and_return("test")
        allow(resource_2).to receive(:id).and_return("test2")
        solr.add resource.to_solr
        solr.add resource_2.to_solr
        solr.commit
        expect(ScannedResource).not_to receive(:find)

        get :manifest, id: "test2", format: :json

        expect(response).to be_success
        response_json = JSON.parse(response.body)
        expect(response_json['@id']).to eq "http://plum.com/concern/scanned_resources/test2/manifest"
      end
    end
  end

  describe 'update' do
    let(:scanned_resource_attributes) { { portion_note: 'Section 2', description: 'a description', source_metadata_identifier: '2028405' } }
    before do
      sign_in user
    end
    context 'by default' do
      it 'updates the record but does not refresh the exernal metadata' do
        post :update, id: scanned_resource, scanned_resource: scanned_resource_attributes
        expect(reloaded.portion_note).to eq 'Section 2'
        expect(reloaded.title).to eq ['Dummy Title']
        expect(reloaded.description).to eq 'a description'
      end
    end
    context 'when :refresh_remote_metadata is set', vcr: { cassette_name: 'bibdata', allow_playback_repeats: true } do
      it 'updates remote metadata' do
        post :update, id: scanned_resource, scanned_resource: scanned_resource_attributes, refresh_remote_metadata: true
        expect(reloaded.title).to eq ['The Giant Bible of Mainz; 500th anniversary, April fourth, fourteen fifty-two, April fourth, nineteen fifty-two.']
      end
    end
  end

  describe "show" do
    before do
      sign_in user
    end
    context "when there's a parent" do
      it "is a success" do
        resource = FactoryGirl.create(:scanned_resource)
        work = FactoryGirl.build(:multi_volume_work)
        work.ordered_members << resource
        work.save
        resource.update_index

        get :show, id: resource.id

        expect(response).to be_success
      end
    end
  end

  describe 'pdf' do
    before do
      sign_in user
    end
    it 'generates the pdf then redirects to its download url' do
      actor = double("Actor")
      allow(controller).to receive(:actor).and_return(actor)
      expect(actor).to receive(:generate_pdf)
      get :pdf, id: scanned_resource
      expect(response).to redirect_to(Rails.application.class.routes.url_helpers.download_path(scanned_resource, file: 'pdf'))
    end
  end

  describe "reorder" do
    let(:resource) { FactoryGirl.create(:scanned_resource) }
    let(:member) { FactoryGirl.create(:file_set) }
    before do
      3.times { resource.ordered_members << member }
      resource.save
      sign_in user
      get :reorder, id: resource.id
    end

    it "finds all proxies for the resource" do
      expect(assigns(:members).map(&:id)).to eq resource.ordered_member_ids
    end
  end

  describe "#save_order" do
    let(:resource) { FactoryGirl.create(:scanned_resource, user: user) }
    let(:member) { FactoryGirl.create(:file_set, user: user) }
    let(:member_2) { FactoryGirl.create(:file_set, user: user) }
    let(:new_order) { resource.ordered_member_ids }
    let(:user) { FactoryGirl.create(:admin) }
    render_views
    before do
      3.times { resource.ordered_members << member }
      resource.ordered_members << member_2
      resource.save
      sign_in user
      post :save_order, id: resource.id, order: new_order, format: :json
    end

    context "when given a new order" do
      let(:new_order) { [member.id, member.id, member_2.id, member.id] }
      it "applies it" do
        expect(response).to be_success
        expect(resource.reload.ordered_member_ids).to eq new_order
      end
    end

    context "when given an incomplete order" do
      let(:new_order) { [member.id] }
      it "fails and gives an error" do
        expect(response).not_to be_success
        expect(JSON.parse(response.body)["message"]).to eq "Order given has the wrong number of elements (should be 4)"
        expect(response).to be_bad_request
      end
    end
  end
end
