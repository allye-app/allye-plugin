/**
 * Re-exports all Allye agent definitions.
 */

import { allyeAgent } from "./allye"
import { allyePlanAgent } from "./allye-plan"
import { allyeBuildAgent } from "./allye-build"
import { allyeReviewAgent } from "./allye-review"
import { allyeDeliverAgent } from "./allye-deliver"

export const agents = {
  allye: allyeAgent,
  "allye-plan": allyePlanAgent,
  "allye-build": allyeBuildAgent,
  "allye-review": allyeReviewAgent,
  "allye-deliver": allyeDeliverAgent,
}
