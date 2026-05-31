# frozen_string_literal: true

Rails.application.routes.draw do
  mount SqlGenius::Engine => "/sql_genius"
end
