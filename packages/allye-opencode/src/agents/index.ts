/**
 * Re-exports all Allye agent definitions.
 */

import { allyeAgent } from "./allye"
import { allyePlanAgent } from "./allye-plan"
import { allyeOrchestratorAgent } from "./allye-orchestrator"
import { allyeBuildAgent } from "./allye-build"
import { allyeReviewAgent } from "./allye-review"
import { allyeDeliverAgent } from "./allye-deliver"

export const agents = {
  allye: allyeAgent,
  "allye-plan": allyePlanAgent,
  "allye-orchestrator": allyeOrchestratorAgent,
  "allye-build": allyeBuildAgent,
  "allye-review": allyeReviewAgent,
  "allye-deliver": allyeDeliverAgent,
}
