# frozen_string_literal: true

RSpec.describe Atcp::CasePagesController do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:regular_user, :user)
  fab!(:moderator)
  fab!(:admin)

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
  end

  describe "anonymous visitors" do
    it "redirects /internal/cases to /login" do
      get "/internal/cases"
      expect(response).to redirect_to("/login")
    end

    it "redirects /internal/cases/:id to /login" do
      get "/internal/cases/5"
      expect(response).to redirect_to("/login")
    end
  end

  describe "logged-in users outside the Internal group" do
    it "returns 403 for a regular user on both URLs" do
      sign_in(regular_user)

      get "/internal/cases"
      expect(response.status).to eq(403)

      get "/internal/cases/5"
      expect(response.status).to eq(403)
    end

    it "returns 403 for a moderator on both URLs" do
      sign_in(moderator)

      get "/internal/cases"
      expect(response.status).to eq(403)

      get "/internal/cases/5"
      expect(response.status).to eq(403)
    end
  end

  describe "Internal access" do
    it "returns 200 for Internal members (non-staff) on both URLs" do
      sign_in(internal_user)

      get "/internal/cases"
      expect(response.status).to eq(200)

      get "/internal/cases/5"
      expect(response.status).to eq(200)
    end

    it "returns 200 for admins on both URLs" do
      sign_in(admin)

      get "/internal/cases"
      expect(response.status).to eq(200)

      get "/internal/cases/5"
      expect(response.status).to eq(200)
    end
  end

  describe "route constraints" do
    it "does not serve a non-numeric :id (404)" do
      sign_in(internal_user)

      get "/internal/cases/abc"
      expect(response.status).to eq(404)
    end
  end

  describe "plugin disabled" do
    it "does not serve the pages when atcp_case_enabled is false (404)" do
      SiteSetting.atcp_case_enabled = false
      sign_in(internal_user)

      get "/internal/cases"
      expect(response.status).to eq(404)
    end
  end
end
