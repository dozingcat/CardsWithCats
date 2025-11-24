import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_bidding.dart';
import 'package:cards_with_cats/cards/card.dart';

String getPromptForBidRequest(BidRequest req) {
  final playerNames = {
    req.playerIndex: "South (you)",
    (req.playerIndex + 1) % 4: "West (opponent)",
    (req.playerIndex + 2) % 4: "North (partner)",
    (req.playerIndex + 3) % 4: "East (opponent)",
  };
  final bidHistoryLines = req.bidHistory
      .map((b) => "${playerNames[b.player]}: ${b.action.toString()}")
      .join("\n");

  final bidHistoryDesc = bidHistoryLines.isEmpty
      ? "You are the opening bidder."
      : "The bid history is:\n$bidHistoryLines";

  return """
You are playing contract bridge. You are South, your partner is North, your opponents are East and West. You and your opponents are using the Standard American bidding system, including:
- 5 card majors (you can support partner's major opening with 3 cards in the suit)
- Weak 2 bids
- Weak jump overcalls
- Negative doubles
- 1NT opening shows 15-17 points
- Stayman and Jacoby transfers after NT openings
  
You will be given a hand and a bid history, and you should return a bid in this JSON format:

{
  "points": The number of high card points in your hand (do not include additional points for distribution, although you may consider your distribution when choosing your response),
  "suitLengths": 4-element array with the number of spades, hearts, diamonds, and clubs in that order.
  "bid": Your bid in the format of '1♠' for suits, '3NT' for no trump, or one of the literal strings 'pass', 'double', or 'redouble',
  "description": A description of what other players can infer about your hand from the bid that you made.
}

For example, if you are the opening bidder and your hand is:
♠AK432 ♥A5 ♦KT98 ♣32

You would return a response like:
{
  "points": 14,
  "suitLengths": [5, 2, 4, 2],
  "bid": "1♠",
  "description": "Shows at least 5 spades and 12 points",
}

Your hand is: ${descriptionWithSuitGroups(req.hand)}

$bidHistoryDesc

What is your bid?
  """
      .trim();
}

Future<BidAction?> getBidFromLlm(BidRequest req) {
  return getBidFromGemini(req);
}

BidAction? extractBidFromLlmResponseText(String responseText) {
  try {
    int lastClosingBraceIndex = responseText.lastIndexOf("}");
    int openingBraceIndexBeforeClosing =
        responseText.lastIndexOf("{", lastClosingBraceIndex);
    final jsonString = responseText.substring(
        openingBraceIndexBeforeClosing, lastClosingBraceIndex + 1);
    final json = jsonDecode(jsonString);
    final bid = json["bid"];
    if (bid is String) {
      return BidAction.fromString(bid);
    }
  } catch (e) {
    print("Error parsing bid: $e");
  }
  return null;
}

Future<BidAction?> getBidFromOllama(BidRequest req) async {
  final prompt = getPromptForBidRequest(req);
  final url = Uri.http("localhost:11434", "/api/generate");
  final model = "gemma3:27b";
  print("Sending prompt (Ollama $model)\n==========\n$prompt\n==========");
  final response = await http.post(url,
      body: json.encode({
        "model": model,
        "prompt": prompt,
        "stream": false,
      }));
  final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
  final responseText = decodedResponse["response"];
  print("=== Response ===\n$responseText\n=== End Response ===\n");
  return extractBidFromLlmResponseText(responseText);
}

const anthropicModels = {
  "opus": "claude-opus-4-20250514", // expensive!
  "sonnet": "claude-sonnet-4-20250514",
  "haiku": "claude-3-5-haiku-20241022",
};

Future<BidAction?> getBidFromClaude(BidRequest req) async {
  final apiKey = "todo-get-from-env-or-prefs";
  final model = anthropicModels["sonnet"]!;
  final prompt = getPromptForBidRequest(req);
  final url = Uri.https("api.anthropic.com", "/v1/messages");
  print("Sending prompt (Anthropic $model)\n==========\n$prompt\n==========");
  final response = await http.post(url,
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: json.encode({
        "model": model,
        "max_tokens": 1024,
        "messages": [
          {
            "role": "user",
            "content": prompt,
          }
        ],
      }));
  final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
  final numInputTokens = decodedResponse["usage"]["input_tokens"];
  final numOutputTokens = decodedResponse["usage"]["output_tokens"];
  final responseText = decodedResponse["content"][0]["text"];
  print(
      "=== Response ($numInputTokens input, $numOutputTokens output) ===\n$responseText\n=== End Response ===\n");
  return extractBidFromLlmResponseText(responseText);
}

const geminiModels = {
  "flash": "gemini-2.5-flash",
  "flash-lite": "gemini-2.5-flash-lite-preview-06-17",
};

Future<BidAction?> getBidFromGemini(BidRequest req) async {
  try {
    const apiKey = "todo-get-from-env-or-prefs";
    final model = geminiModels["flash"]!;
    final prompt = getPromptForBidRequest(req);
    final url = Uri.https("generativelanguage.googleapis.com",
        "/v1beta/models/$model:generateContent");
    print("Sending prompt (Google $model)\n====================\n");
    final response = await http.post(url,
        headers: {
          "x-goog-api-key": apiKey,
          "content-type": "application/json",
        },
        body: json.encode({
          "contents": [
            {
              "parts": [
                {
                  "text": prompt,
                }
              ]
            }
          ]
        }));
    final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
    final responseText =
        decodedResponse["candidates"][0]["content"]["parts"][0]["text"];
    print("=== Response ===\n$responseText\n=== End Response ===\n");
    return extractBidFromLlmResponseText(responseText as String);
  } catch (e) {
    print("Error: $e");
    return null;
  }
}
