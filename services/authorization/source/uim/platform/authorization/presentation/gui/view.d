module neko.service.authorization.presentation.gui.view;

import neko.service.authorization;

mixin(ShowModule!());

@safe:

class AuthorizationGuiView {
  string renderWindow(string title) {
    return "[GUI] " ~ title ~ " - widgets can be bound to the GUI model.";
  }
}
