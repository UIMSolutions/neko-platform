module neko.authorization.presentation.cli.controller;

import neko.authorization;

mixin(ShowModule!());

@safe:

class AuthorizationCliController {
  protected AuthorizationCliModel model;
  private AuthorizationCliView view;

  this(AuthorizationCliModel model, AuthorizationCliView view) {
    this.model = model;
    this.view = view;
  }

  void printSummary(string tenantId) {
    view.renderSummary(  tenantId,
      model.applicationCount(tenantId),
      model.policyCount(tenantId),
      model.assignmentCount(tenantId)
    );
  }
}
