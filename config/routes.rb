# frozen_string_literal: true

SolidusNexi::Engine.routes.draw do
  post "webhooks/:payment_method_id", to: "webhooks#create", as: :webhook
  post "checkout_sessions", to: "checkout_sessions#create", as: :checkout_sessions
  get "returns/:token", to: "returns#show", as: :return
  get "cancels/:token", to: "returns#cancel", as: :cancel
end
