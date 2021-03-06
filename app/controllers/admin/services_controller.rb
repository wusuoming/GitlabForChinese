class Admin::ServicesController < Admin::ApplicationController
  include ServiceParams

  before_action :service, only: [:edit, :update]

  def index
    @services = services_templates
  end

  def edit
    unless service.present?
      redirect_to admin_application_settings_services_path,
        alert: "服务未知或不存在"
    end
  end

  def update
    if service.update_attributes(service_params[:service])
      redirect_to admin_application_settings_services_path,
        notice: '应用设置保存成功'
    else
      render :edit
    end
  end

  private

  def services_templates
    Service.available_services_names.map do |service_name|
      service_template = service_name.concat("_service").camelize.constantize
      service_template.where(template: true).first_or_create
    end
  end

  def service
    @service ||= Service.where(id: params[:id], template: true).first
  end
end
