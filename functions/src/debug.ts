import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const debugCreateNotification = functions.https.onRequest(
  async (req, res) => {
    const userId = req.query.userId as string;

    if (!userId) {
      res.status(400).send("Missing userId query parameter");
      return;
    }

    try {
      const ref = admin.firestore().collection("Notifications").doc();
      await ref.set({
        userId: userId,
        n_type: "debug_test",
        n_params: {message: "This is a test notification from debug function"},
        n_read: false,
        n_sender_fullname: "Debug System",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).send(
        `Notification created successfully with ID: ${ref.id}`
      );
    } catch (error) {
      console.error("Error creating notification:", error);
      res.status(500).send(`Error creating notification: ${error}`);
    }
  });
