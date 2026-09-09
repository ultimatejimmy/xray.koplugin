-- Keep both upstream helper spellings bound to the same mock environment.
-- Fail immediately if a real JSON implementation is unavailable.
require("dkjson")
require("spec.spec_helper")
package.loaded["spec/spec_helper"] = package.loaded["spec.spec_helper"]
