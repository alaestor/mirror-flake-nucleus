{ lib }:
let
  compact =
    value:
    if builtins.isAttrs value then
      lib.filterAttrs (_: child: child != null && child != { }) (lib.mapAttrs (_: compact) value)
    else
      value;
in
{
  description,
  inputs,
  # The module option owns the default outputs expression.
  outputsExpression,
}:
''
  # DO-NOT-EDIT. Generated from nucleus declarations.
  {
    description = ${builtins.toJSON description};

    outputs = ${outputsExpression};

    inputs = ${lib.generators.toPretty { } (compact inputs)};
  }
''
