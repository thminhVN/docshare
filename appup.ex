# Application upgrade instructions (OTP appup), in Elixir form.
# The :appup compiler (Forecastle) evaluates this file and writes
# `docshare.appup` into the release's ebin so relups can be generated.
#
# Format: {NewVsn, [{FromVsn, UpInstructions}], [{FromVsn, DownInstructions}]}
# Versions are charlists and MUST match the `version:` in mix.exs.
#
# For each release you hot-upgrade, bump this to the new version and describe
# how to get there from the previous one. Common instructions:
#
#   {:update, MyMod, {:advanced, []}}  -> stateful process; calls code_change/3
#   {:load_module, MyMod}              -> stateless module; just reload it
#   {:add_module, MyMod}               -> brand new module
#   {:delete_module, MyMod}            -> removed module
#
# `mix castle.relup` can usually infer simple module loads for you; you mainly
# hand-write entries for GenServers/LiveViews that hold state.
#
# Example for the next release (0.2.0 from 0.1.0):
#
#   {~c"0.2.0",
#    [{~c"0.1.0", [{:load_module, DocshareWeb.DocumentLive.Show}]}],
#    [{~c"0.1.0", [{:load_module, DocshareWeb.DocumentLive.Show}]}]}

{~c"0.1.4",
 [
   {~c"0.1.3",
    [
      {:load_module, DocshareWeb.Layouts},
      {:load_module, DocshareWeb.PageHTML},
      {:load_module, DocshareWeb.DocumentLive.Show}
    ]}
 ],
 [
   {~c"0.1.3",
    [
      {:load_module, DocshareWeb.Layouts},
      {:load_module, DocshareWeb.PageHTML},
      {:load_module, DocshareWeb.DocumentLive.Show}
    ]}
 ]}
