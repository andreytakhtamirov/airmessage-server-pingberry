import Foundation

struct NotificationPayload: Codable {
    let recipient_email: String
    let message_title: String
    let message_body: String
    let method: String
    let queue_if_offline: Bool
    let collapse_duplicates: Bool
}

class PingBerryService {
    private let baseURL = URL(string: "https://api.pingberry.xyz/notify")!
    private var lastSentTimestamps: [String: Date] = [:]
    private let queue = DispatchQueue(label: "pingberryNotificationQueue")
    private let totalMessageByteLimit = 245

    func sendNotification(pingberryEmail: String, messages: [MessageInfo], completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard !messages.isEmpty else {
                completion(.failure(NSError(domain: "pingberry", code: 0, userInfo: [NSLocalizedDescriptionKey: "No messages to send"])))
                return
            }

            let count = messages.count
            let perMessageByteLimit = self.totalMessageByteLimit / count
            
            var notificationBody = ""

            if count == 1, let message = messages.first {
                // Single-message notification
                let rawTitle = "iMessage - " + (message.sender ?? "Unknown sender")
                let title = self._truncateToBytes(rawTitle, limit: self.totalMessageByteLimit)
                
                let body = self._truncateToBytes(self._displayText(for: message), limit: perMessageByteLimit)
                
                self._sendNotification(
                    pingberryEmail: pingberryEmail,
                    message_title: title,
                    message_body: body,
                    completion: completion
                )
            } else {
                // Multi-message notification
                let rawTitle = "iMessage (\(messages.count))"
                let title = self._truncateToBytes(rawTitle, limit: self.totalMessageByteLimit)
                
                for message in messages {
                    let sender = message.sender ?? "Unknown sender"
                    let senderBytes = (sender + "\n").utf8.count

                    let body = self._displayText(for: message)
                    let availableBytes = max(perMessageByteLimit - senderBytes, 0)
                    
                    let truncatedBody = self._truncateToBytes(body, limit: availableBytes)
                    
                    notificationBody += "\(sender)\n\(truncatedBody)\n"
                }
                
                notificationBody = notificationBody.trimmingCharacters(in: .whitespacesAndNewlines)
                
                self._sendNotification(
                    pingberryEmail: pingberryEmail,
                    message_title: title,
                    message_body: notificationBody,
                    collapse_duplicates: false,
                    completion: completion
                )
            }
        }
    }
    
    private func _displayText(for message: MessageInfo) -> String {
        if !message.attachments.isEmpty {
            return "Sent a Photo"
        } else if !message.stickers.isEmpty {
            return "Sent a Sticker"
        } else if let text = message.text, !text.isEmpty {
            return text
        } else {
            return "Unknown Message"
        }
    }
    
    private func _truncateToBytes(_ string: String, limit: Int) -> String {
        var truncated = ""
        var bytesCount = 0

        for char in string {
            let charBytes = String(char).utf8.count
            if bytesCount + charBytes > limit - 3 { // reserve 3 bytes for ellipsis
                truncated += "…"
                break
            }
            truncated.append(char)
            bytesCount += charBytes
        }

        return truncated
    }

    private func _sendNotification(pingberryEmail: String, message_title: String, message_body: String, collapse_duplicates: Bool = true, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = NotificationPayload(
            recipient_email: pingberryEmail,
            message_title: message_title,
            message_body: message_body,
            method: "mqtt",
            queue_if_offline: false,
            collapse_duplicates: true,
        )

        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData
            print("[PingBerry Service] Sending notification: \(payload)")
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // Check for valid HTTP response and successful status code (200...299)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let error = NSError(domain: "InvalidStatusCode", code: statusCode, userInfo: nil)

                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "NoData", code: -1, userInfo: nil)))
                    return
                }

                if let responseString = String(data: data, encoding: .utf8) {
                    completion(.success(responseString))
                } else {
                    completion(.failure(NSError(domain: "InvalidResponse", code: -2, userInfo: nil)))
                }
            }
        }

        task.resume()
    }
}
