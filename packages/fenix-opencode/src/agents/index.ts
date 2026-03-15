/**
 * Re-exports all Fenix agent definitions.
 */

import { fenixAgent } from "./fenix"
import { fenixPlanAgent } from "./fenix-plan"
import { fenixBuildAgent } from "./fenix-build"
import { fenixReviewAgent } from "./fenix-review"
import { fenixDeliverAgent } from "./fenix-deliver"

export const agents = {
  fenix: fenixAgent,
  "fenix-plan": fenixPlanAgent,
  "fenix-build": fenixBuildAgent,
  "fenix-review": fenixReviewAgent,
  "fenix-deliver": fenixDeliverAgent,
}
