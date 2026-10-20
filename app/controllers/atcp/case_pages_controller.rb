# frozen_string_literal: true

module Atcp
  class CasePagesController < ::ApplicationController
    include Atcp::InternalAccessGuard

    requires_plugin "discourse-atcp-case"

    skip_before_action :check_xhr
    before_action :redirect_to_login_if_anonymous
    before_action :ensure_internal_access!

    def index
      render "default/empty"
    end

    def show
      render "default/empty"
    end

    private

    def redirect_to_login_if_anonymous
      redirect_to_login if current_user.nil?
    end
  end
end
