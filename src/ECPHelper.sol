// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// --- ECP Structs and Interface ---
struct MetadataEntry {
    bytes32 key;
    bytes value;
}

struct ECPCommentData {
    address author;
    address app;
    uint256 channelId;
    uint256 deadline;
    bytes32 parentId;
    uint8 commentType;
    string content;
    MetadataEntry[] metadata;
    string targetUri;
}

interface ICommentManager {
    function postComment(
        ECPCommentData calldata commentData,
        bytes calldata appSignature
    ) external returns (bytes32 commentId);
}
// --- End ECP Structs and Interface ---

library ECPHelper {
    uint256 public constant DEFAULT_CHANNEL_ID = 0;
    uint8 public constant DEFAULT_COMMENT_TYPE = 0;
    uint256 public constant COMMENT_DEADLINE_OFFSET = 1 days;

    function postCommentAndGetId(
        ICommentManager commentManager,
        uint256 channelIdParam,
        bytes32 parentIdParam,
        string memory contentParam,
        address authorAndAppAddress
    ) internal returns (bytes32 commentId) {
        if (address(commentManager) == address(0)) {
            return bytes32(0);
        }

        ECPCommentData memory commentData = ECPCommentData({
            author: authorAndAppAddress, // SourceAsserter contract is the author
            app: authorAndAppAddress, // SourceAsserter contract is the app
            channelId: channelIdParam, // Use the provided channel ID
            deadline: block.timestamp + COMMENT_DEADLINE_OFFSET, // Comment deadline
            parentId: parentIdParam,
            commentType: DEFAULT_COMMENT_TYPE, // Default comment type
            content: contentParam,
            metadata: new MetadataEntry[](0), // Empty metadata array
            targetUri: "" // Always set targetUri to empty string
        });

        commentId = commentManager.postComment(commentData, bytes(""));

        return commentId;
    }
}
