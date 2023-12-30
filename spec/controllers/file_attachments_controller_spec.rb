require "spec_helper"

RSpec.describe FileAttachmentsController, type: :controller do
  describe "GET /file_attachments" do
    before do
      sign_in users(:superadmin)
    end

    it "renders correctly and without errors" do
      expect {
        get :index
      }.not_to raise_error
    end
  end
end
