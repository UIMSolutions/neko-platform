module neko.service.authorization.presentation.gui.controller;

import neko.service.authorization;

mixin(ShowModule!());

@safe:

class AuthorizationGuiController {
  protected AuthorizationGuiModel model;
  private AuthorizationGuiView view;

  this(AuthorizationGuiModel model, AuthorizationGuiView view) {
    this.model = model;
    this.view = view;
  }

  string render() {
    return view.renderWindow(model.windowTitle());
  }
}
